#! /usr/bin/env python
# pylint: disable=too-many-locals

"""Query and optionally download data from Sentinels Scientific Data Hub

Usage
-----

For help on using this script, type:

ceos_dhusget.py -h

at command line.

"""

import argparse
import os
import logging
import hashlib
from datetime import datetime
import requests
from lxml import html
import numpy as np

__version__ = "0.2.0"


def dhus_download(prod_tups, download, download_dir, auth):
    """Given list of tuples, download DHuS product or manifest.

    Parameters
    ----------
    prod_tups : list
        List of tuples with titles, URIs, and UUIDs to download.
    download : string
        String indicating what to download: 'manifest', 'product', or 'MD5'.
    download_dir: string
        String indicating path to download directory.
    auth : tuple
        Tuple with user and password to authenticate to DHuS.

    Note
    ----
    The UUID element of parameter `prod_tups` is currently ignored.
    """

    chunk_size_base = 1024      # this may need more scrutiny

    if download == "manifest":
        # Skeleton string to receive prefix URI and UUID for one product.
        # Note there's a trailing slash on the URI in {0}
        uri_skel = "{0}Nodes('{1}.SAFE')/Nodes('manifest.safe')/$value"
        chunk_size = chunk_size_base
    else:
        # Skeleton string to receive prefix URI for one product
        # Note there's a trailing slash on the URI in {}
        uri_skel = "{}$value"
        uri_skel_md5 = "{}Checksum/Value/$value"
        chunk_size = chunk_size_base ** 2  # we can get very large files

    if not os.path.exists(download_dir):
        os.mkdir(download_dir)

    failed_tups = []
    for title, uri, uuid in prod_tups:

        if download == "manifest":
            dwnld_uri = uri_skel.format(uri, title)
            fname = os.path.join(download_dir, title + "_manifest_safe")
        else:
            dwnld_uri = uri_skel.format(uri)
            md5_uri = uri_skel_md5.format(uri)
            fname = os.path.join(download_dir, title)

        if os.path.exists(fname):
            logger.warning("Skipping existing file: %s", fname)
            continue
        else:
            uri_conn = requests.get(dwnld_uri, auth=auth, stream=True)
            logger.info("Downloading %s %s", download, title)
            with open(fname, "w") as dwnf:
                for chunk in uri_conn.iter_content(chunk_size):
                    dwnf.write(chunk)
            with open(fname, "rb") as f:
                md5_local = hashlib.md5(f.read()).hexdigest()
            md5_remote = requests.get(md5_uri, auth=auth)
            if md5_local.upper() != md5_remote.content:
                logger.error("Failed MD5 checksum %s %s %s",
                             title, uri, uuid)
                failed_tups.append(title, uri, uuid)

    tstampfn = os.path.join(download_dir, ".last_time_stamp")
    failed_md5 = os.path.join(download_dir, ".failed_md5")
    with open(tstampfn, "w") as tstampf:
        tstampf.write(datetime.utcnow().isoformat())

    if len(failed_tups > 0):
        with open(failed_md5, "w") as failedf:
            for tup in failed_tups:
                failedf.write(" ".join(str(x) for x in tup) + "\n")


def mkqry_polygons(coordinates, max_len=10):
    """Construct polygon-subsetting part of DHuS query.

    If the requested coordinates imply an area larger than 10 degrees in
    either dimension, then return a series of query strings with smaller
    subpolygons covering the requested area.

    Parameters
    ----------
    coordinates : list
        List of 4 elements (lon1, lat1, lon2, lat2) with longitude and
        latitude coordinates for lower left and upper right corners of
        area of interest rectangle.
    max_len : scalar or list
        Maximum length (decimal geographical degrees) for sides of area
        of interest rectangle.  If scalar, it applies to both `x` and `y`
        coordinates, otherwise a 2-element list specifying maximum length
        for `x` and `y`, respectively.

    Returns
    -------
    A list of strings corresponding to the polygon query for each subpolygon
    generated.  The first and last vertices of each subpolygon are the same
    for closure.
    """

    xstep = max_len if np.isscalar(max_len) else max_len[0]
    ystep = max_len if np.isscalar(max_len) else max_len[1]
    lons = [coordinates[0], coordinates[2]]
    lats = [coordinates[1], coordinates[3]]
    xy_range = [np.diff(lons), np.diff(lats)]

    if np.any(xy_range < 0):
        msg = ("Upper right coordinates must be larger than "
               "lower left coordinates.")
        raise Exception(msg)

    qry_beg = "(footprint:\"Intersects(POLYGON(("
    qry_end = ")))\")"
    polygs = []

    if xy_range[0] > xstep or xy_range[1] > ystep:
        # Calculate how many samples we need for linspace.  The ceiling is
        # required to cover the last step, and then add 2 to accomodate for
        # the inclusion of the end points.
        xn = np.ceil(xy_range[0] / xstep) + 2
        yn = np.ceil(xy_range[1] / ystep) + 2
        xgrd = np.linspace(lons[0], lons[1], xn)
        ygrd = np.linspace(lats[0], lats[1], yn)
        # Create longitude and latitude grids of dimension (yn, xn).  The
        # elements of the longitude grid are the longitude coordinates
        # along the rows, where rows are identical.  The elements of the
        # latitude grid are the latitude coordinates along the columns,
        # where columns are identical.
        longrd, latgrd = np.meshgrid(xgrd, ygrd, sparse=False)
        # Above is just an indexing trick to allow us to loop through each
        # longitude and latitude properly below.  Note that the last
        # coordinates are excluded from the looping indices since we need
        # to reach current coordinate plus one.
        for i in range(int(xn) - 1):
            for j in range(int(yn) - 1):
                verts = [(longrd[j, i], latgrd[j, i]),     # lower left
                         (longrd[j, i + 1], latgrd[j, i]),  # lower right
                         (longrd[j, i + 1], latgrd[j + 1, i]),  # upper right
                         (longrd[j, i], latgrd[j + 1, i]),  # upper left
                         (longrd[j, i], latgrd[j, i])]      # close
                poly_fstr = ("{0[0][0]:.13f} {0[0][1]:.13f}, "
                             "{0[1][0]:.13f} {0[1][1]:.13f}, "
                             "{0[2][0]:.13f} {0[2][1]:.13f}, "
                             "{0[3][0]:.13f} {0[3][1]:.13f}, "
                             "{0[4][0]:.13f} {0[4][1]:.13f}")
                polygs.append(qry_beg + poly_fstr.format(verts) + qry_end)
    else:
        poly_fstr = ("{0[0]:.13f} {0[1]:.13f}, "  # lower left
                     "{0[2]:.13f} {0[1]:.13f}, "  # lower right
                     "{0[2]:.13f} {0[3]:.13f}, "  # upper right
                     "{0[0]:.13f} {0[3]:.13f}, "  # upper left
                     "{0[0]:.13f} {0[1]:.13f}")   # close
        polygs.append(qry_beg + poly_fstr.format(coordinates) + qry_end)

    return polygs


def mkqry_statement(mission_name, instrument_name, time_since,
                    coordinates, product, time_file=None,
                    ingestion_time_from="1970-01-01T00:00:00.000Z",
                    ingestion_time_to="NOW",
                    sensing_time_from="1970-01-01T00:00:00.000Z",
                    sensing_time_to="NOW"):
    """Construct the OpenSearch query statement for DHuS URI.

    Returns
    -------
    A list of strings corresponding to a query string to send to DHuS.
    """

    main_opts = [mission_name, instrument_name, time_since, coordinates,
                 product, time_file, ingestion_time_from, ingestion_time_to,
                 sensing_time_from, sensing_time_to]
    if all(v is None for v in main_opts):
        qry_statement = ["*"]
    else:
        qry_statement = []
        if mission_name is not None:
            qry_statement.append("platformname:{}".format(product))
        if instrument_name is not None:
            qry_statement.append("instrumentshortname:{}".format(product))
        if product is not None:
            qry_statement.append("producttype:{}".format(product))
        # Subset with time_since, time_file, ingestion_time_from,
        # ingestion_time_to
        ingestion_opts = [main_opts[i] for i in [2, 5, 6, 7]]
        # Check if we need to set ingestiondate time subquery
        if any(v is not None for v in ingestion_opts):
            time_str = "ingestiondate:[{0} TO {1}]"
            if time_file is not None and ingestion_time_to is not None:
                try:
                    with time_file:  # file already opened
                        time_infile = time_file.readline().strip()
                        time_subqry = time_str.format(time_infile,
                                                      ingestion_time_to)
                except Exception:
                    dflt_last = "1970-01-01T00:00:00.000Z"
                    time_subqry = time_str.format(dflt_last,
                                                  ingestion_time_to)
                    logger.warning("Could not read time stamp in file; "
                                   "assuming %s", dflt_last)
            elif time_since is not None:  # modify time_str
                time_str = "ingestiondate:[NOW-{}HOURS TO NOW]"
                time_subqry = time_str.format(time_since)
            else:  # assume ingestion_time_* args not None (defaults)
                time_subqry = time_str.format(ingestion_time_from,
                                              ingestion_time_to)
            # Now we have a time subquery
            qry_statement.append(time_subqry)

        if sensing_time_from is not None and sensing_time_to is not None:
            sensing_subqry = "beginPosition:[{0} TO {1}]"
            qry_statement.append(sensing_subqry.format(sensing_time_from,
                                                       sensing_time_to))

        # Remove empty query elements and join the rest into single string
        qry_statement = [x for x in qry_statement if x]
        qry_statement = " AND ".join(qry_statement)
        if coordinates is not None:
            # The polygon string constructor takes the coordinates in the
            # order given in command line.  The DHuS limits searches to
            # polygons 10 degrees square.
            geo_subqry = mkqry_polygons(coordinates, max_len=10)
            for idx, item in enumerate(geo_subqry):
                item_new = [x for x in [qry_statement, item] if x]
                geo_subqry[idx] = " AND ".join(item_new)
            qry_statement = geo_subqry
        else:
            qry_statement = [qry_statement]

    return qry_statement


def main(dhus_uri, user, password, **kwargs):
    """Query, and optionally, download products from DHuS Data Hub

    See parser help for description of arguments.  All arguments are
    coerced to string during execution.
    """
    mission_name = kwargs.pop("mission_name")
    instrument_name = kwargs.pop("instrument_name")
    time_since = kwargs.pop("time_since")
    ingestion_time_from = kwargs.pop("ingestion_time_from")
    ingestion_time_to = kwargs.pop("ingestion_time_to")
    sensing_time_from = kwargs.pop("sensing_time_from")
    sensing_time_to = kwargs.pop("sensing_time_to")
    coordinates = kwargs.pop("coordinates")
    product = kwargs.pop("product")
    download = kwargs.pop("download")
    time_file = kwargs.pop("time_file")

    # Prepare list of search queries from criteria requested
    qry_statement = mkqry_statement(mission_name=mission_name,
                                    instrument_name=instrument_name,
                                    time_since=time_since,
                                    coordinates=coordinates,
                                    product=product, time_file=time_file,
                                    ingestion_time_from=ingestion_time_from,
                                    ingestion_time_to=ingestion_time_to,
                                    sensing_time_from=sensing_time_from,
                                    sensing_time_to=sensing_time_to)

    titles = []
    uuids = []
    root_uris = []
    for qry in qry_statement:
        # The final query URI is ready to be created
        qry_uri = (dhus_uri + "/search?q=" + qry + "&rows=100&start=0")
        dhus_qry = requests.get(qry_uri, auth=(user, password))
        qry_tree = html.fromstring(dhus_qry.content)
        # Retrieve titles and UUIDs from 'title' and 'id' tags under
        # 'entry'
        titles.append(qry_tree.xpath("//entry/title/text()"))
        uuids.append(qry_tree.xpath("//entry/id/text()"))
        # Retrieve product and product root URI from links under entry.  We
        # assume the former doesn't have any 'rel' tag, and the latter has
        # the 'alternative' tag.
        # prod_uris = qry_tree.xpath("//entry//link[not(@rel)]/@href")
        root_uri_xpath = "//entry//link[@rel='alternative']/@href"
        root_uris.append(qry_tree.xpath(root_uri_xpath))

    # Flatten lists (we ended up with one list per subpolygon search).
    # These may contain duplicates at the boundary of each subpolygon.
    titles = [y for x in titles for y in x]
    uuids = [y for x in uuids for y in x]
    root_uris = [y for x in root_uris for y in x]
    # Remove duplicates with set(); forget ordering
    prods = list(set(zip(titles, root_uris, uuids)))

    if len(prods) > 0:
        with open("qry_results", "w") as qryfile:
            for tup in prods:
                qryfile.write(" ".join(str(x) for x in tup) + "\n")
        manif_dir = "MANIFEST"
        prod_dir = "PRODUCT"
        if download is None:
            msg = ("No downloads requested; product names and UUIDs "
                   "written to file: qry_results")
            logger.info(msg)
        elif download == "manifest":
            dhus_download(prods, download="manifest",
                          download_dir=manif_dir, auth=(user, password))
        elif download == "product":
            dhus_download(prods, download="product",
                          download_dir=prod_dir, auth=(user, password))
        else:
            dhus_download(prods, download="manifest",
                          download_dir=manif_dir, auth=(user, password))
            dhus_download(prods, download="product",
                          download_dir=prod_dir, auth=(user, password))
    else:
        logger.info("No products match search criteria.")


if __name__ == "__main__":
    _DESCRIPTION = ("Non-interactive Sentinels product (or manifest) "
                    "retriever from Scientific Data Hub.")
    _FORMATERCLASS = argparse.ArgumentDefaultsHelpFormatter
    parser = argparse.ArgumentParser(description=_DESCRIPTION,
                                     formatter_class=_FORMATERCLASS)
    group = parser.add_argument_group("required arguments")
    parser.add_argument("dhus_uri", metavar="dhus-uri",
                        help="DHuS root URI, without trailing slash ('/').")
    group.add_argument("-u", "--user", required=True,
                       help="Registered Data Hub user name.")
    group.add_argument("-p", "--password", required=True,
                       help="Password for registered Data Hub user.")
    parser.add_argument("-m", "--mission-name",
                        choices=["Sentinel-1", "Sentinel-2", "Sentinel-3"],
                        help="Mission name.")
    parser.add_argument("-i", "--instrument-name",
                        choices=["SAR", "MSI", "OLCI", "SLSTR", "SRAL"],
                        help="Instrument name.")
    parser.add_argument("-t", "--time-since", type=int,
                        help=("Number of hours (integer) since the time "
                              "the request is made to search for products"))
    parser.add_argument("-s", "--ingestion-time-from",
                        default="1970-01-01T00:00:00.000Z",
                        help=("Search for products ingested after the "
                              "specified timestamp, in ISO-8601 format "
                              "YYYY-MM-DDThh:mm:ss.cccZ; "
                              "e.g. 2016-10-02T06:00:00.000Z"))
    parser.add_argument("-e", "--ingestion-time-to",
                        default="NOW",
                        help=("Search for products ingested before the "
                              "specified timestamp, in ISO_8601 format "
                              "YYYY-MM-DDThh:mm:ss.cccZ; "
                              "e.g. 2016-10-02T06:00:00.000Z"))
    parser.add_argument("-S", "--sensing-time-from",
                        default="1970-01-01T00:00:00.000Z",
                        help=("Search for products with sensing timestamp "
                              "greater than the specified timestamp, in "
                              "ISO-8601 format YYYY-MM-DDThh:mm:ss.cccZ; "
                              "e.g. 2016-10-02T06:00:00.000Z"))
    parser.add_argument("-E", "--sensing-time-to",
                        default="NOW",
                        help=("Search for products with sensing timestamp "
                              "smaller than the specified timestamp, in "
                              "ISO-8601 format YYYY-MM-DDThh:mm:ss.cccZ; "
                              "e.g. 2016-10-02T06:00:00.000Z"))
    parser.add_argument("-c", "--coordinates", nargs=4, type=float,
                        metavar=("lon1", "lat1", "lon2", "lat2"),
                        help=("Geographical coordinates of two opposite "
                              "vertices of rectangular area to search for."))
    parser.add_argument("-T", "--product",
                        choices=["SLC", "GRD", "OCN", "RAW", "S2MSI1C"],
                        help=("Product type to search. S2MSI1C is for "
                              "Sentinel-2 only"))
    parser.add_argument("-d", "--download",
                        choices=["manifest", "product", "all"],
                        help=("What to download. If not prodived, only "
                              "UUID and product names are downloaded."))
    parser.add_argument("-f", "--time-file", type=argparse.FileType("r"),
                        help=("Path to file containing the time of last "
                              "successful download."))
    parser.add_argument("--version", action="version",
                        version="%(prog)s {}".format(__version__))
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    main(args.dhus_uri, args.user, args.password,
         mission_name=args.mission_name, instrument_name=args.instrument_name,
         time_since=args.time_since,
         ingestion_time_from=args.ingestion_time_from,
         ingestion_time_to=args.ingestion_time_to,
         sensing_time_from=args.sensing_time_from,
         sensing_time_to=args.sensing_time_to,
         coordinates=args.coordinates, product=args.product,
         download=args.download, time_file=args.time_file)

else:
    logging.basicConfig()
    logger = logging.getLogger(__name__)
