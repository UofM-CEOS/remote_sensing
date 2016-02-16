#! /usr/bin/env python
# pylint: disable=too-many-locals

"""Query and optionally download data from Sentinel-1 Data Hub.

Usage
-----

For help on using this script, type:

ceos_dhusget.py -h

at command line.
"""

import os
from datetime import datetime
import requests
from lxml import html
import numpy as np

__version__ = "0.1.0"

def dhus_download(prod_tups, download, download_dir, auth):
    """Given list of tuples, download DHuS product or manifest.

    Parameters
    ----------
    prod_tups : list
        List of tuples with titles, URIs, and UUIDs to download.
    download : string
        String indicating what to download: 'manifest' or 'product'.
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
        # Skeleton string to receive prefix URI and UUID for one product
        uri_skel = "{0}/Nodes('{1}.SAFE')/Nodes('manifest.safe')/$value"
        chunk_size = chunk_size_base
    else:
        # Skeleton string to receive prefix URI for one product
        uri_skel = "{}/$value"
        chunk_size = chunk_size_base ** 2  # we can get very large files

    if not os.path.exists(download_dir):
        os.mkdir(download_dir)

    for title, uri, uuid in prod_tups:

        if download == "manifest":
            dwnld_uri = uri_skel.format(uri, title)
            fname = os.path.join(download_dir, title + "_manifest_safe")
        else:
            dwnld_uri = uri_skel.format(uri)
            fname = os.path.join(download_dir, title)

        if os.path.exists(fname):
            print "Skipping existing file: {}".format(fname)
            continue
        else:
            uri_conn = requests.get(dwnld_uri, auth=auth, stream=True)
            print "Downloading {0} {1}".format(download, title)
            with open(fname, "w") as dwnf:
                for chunk in uri_conn.iter_content(chunk_size):
                    dwnf.write(chunk)

    tstampfn = os.path.join(download_dir, ".last_time_stamp")
    with open(tstampfn, "w") as tstampf:
        tstampf.write(datetime.utcnow().isoformat())


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
                verts = [(longrd[j, i], latgrd[j, i]), # lower left
                         (longrd[j, i + 1], latgrd[j, i]), # lower right
                         (longrd[j, i + 1], latgrd[j + 1, i]), # upper right
                         (longrd[j, i], latgrd[j + 1, i]),     # upper left
                         (longrd[j, i], latgrd[j, i])]         # close
                poly_fstr = ("{0[0][0]:.13f} {0[0][1]:.13f}, "
                             "{0[1][0]:.13f} {0[1][1]:.13f}, "
                             "{0[2][0]:.13f} {0[2][1]:.13f}, "
                             "{0[3][0]:.13f} {0[3][1]:.13f}, "
                             "{0[4][0]:.13f} {0[4][1]:.13f}")
                polygs.append(qry_beg + poly_fstr.format(verts) + qry_end)
    else:
        poly_fstr = ("{0[0]:.13f} {0[1]:.13f}, " # lower left
                     "{0[2]:.13f} {0[1]:.13f}, " # lower right
                     "{0[2]:.13f} {0[3]:.13f}, " # upper right
                     "{0[0]:.13f} {0[3]:.13f}, " # upper left
                     "{0[0]:.13f} {0[1]:.13f}")  # close
        polygs.append(qry_beg + poly_fstr.format(coordinates) + qry_end)

    return polygs


def mkqry_statement(time_since, time_file, coordinates, product):
    """Construct the OpenSearch query statement for DHuS URI.

    Returns
    -------
    A list of strings corresponding to a query string to send to DHuS.
    """

    if (time_since is None and time_file is None and
        coordinates is None and product is None):
        qry_statement = ["*"]
    else:
        qry_statement = []

        if product is not None:
            qry_statement.append("producttype:{}".format(product))

        if time_since is not None or time_file is not None:
            if time_since is not None: # overrides time_file
                time_str = "ingestiondate:[NOW-{}HOURS TO NOW]"
                time_subqry = time_str.format(time_since)
            else:               # we have time_file
                time_str = "ingestiondate:[{} TO NOW]"
                try:
                    with time_file: # file already opened
                        time_infile = time_file.readline().strip()
                        time_subqry = time_str.format(time_infile)
                except Exception:
                    dflt_last = "1970-01-01T00:00:00.000Z"
                    time_subqry = time_str.format(dflt_last)
                    print ("Could not read time stamp in file; "
                           "assuming {}".format(dflt_last))
            # Now we have a time subquery
            qry_statement.append(time_subqry)

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

    return qry_statement


def main(dhus_uri, user, password, **kwargs):
    """Query, and optionally, download products from DHuS Data Hub.

    See parser help for description of arguments.  All arguments are
    coerced to string during execution.
    """

    time_since = kwargs.get("time_since")
    time_file = kwargs.get("time_file")
    coordinates = kwargs.get("coordinates")
    product = kwargs.get("product")
    download = kwargs.get("download")

    # Prepare list of search queries from criteria requested
    qry_statement = mkqry_statement(time_since, time_file,
                                    coordinates, product)

    titles = []; uuids = []; root_uris = []
    for qry in qry_statement:
        # The final query URI is ready to be created
        qry_uri = (dhus_uri + "/search?q=" + qry + "&rows=10000&start=0")
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
            print msg
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
        print "No products match search criteria."


if __name__ == "__main__":
    import argparse
    _DESCRIPTION = ("Non-interactive Sentinel-1 product (or manifest) "
                    "retriever from a Data Hub instance.")
    parser = argparse.ArgumentParser(description=_DESCRIPTION)
    group = parser.add_argument_group("required arguments")
    parser.add_argument("dhus_uri", metavar="dhus-uri",
                        help="DHuS root URI, without trailing slash ('/').")
    group.add_argument("-u", "--user", required=True,
                       help="Registered Data Hub user name.")
    group.add_argument("-p", "--password", required=True,
                       help="Password for registered Data Hub user.")
    parser.add_argument("-t", "--time-since", type=int,
                        help=("Number of hours (integer) since the time "
                              "the request is made to search for products"))
    parser.add_argument("-f", "--time-file", type=argparse.FileType("r"),
                        help=("Path to file containing the time of last "
                              "successful download."))
    parser.add_argument("-c", "--coordinates", nargs=4, type=float,
                        metavar=("lon1", "lat1", "lon2", "lat2"),
                        help=("Geographical coordinates of two opposite "
                              "vertices of rectangular area to search for."))
    parser.add_argument("-T", "--product",
                        choices=["SLC", "GRD", "OCN", "S2MSI1C"],
                        help="Product type to search.")
    parser.add_argument("-d", "--download",
                        choices=["manifest", "product", "all"],
                        help=("What to download. If not prodived, only "
                              "UUID and product names are downloaded."))
    parser.add_argument("--version", action="version",
                        version="%(prog)s {}".format(__version__))
    args = parser.parse_args()
    main(args.dhus_uri, args.user, args.password,
         time_since=args.time_since, time_file=args.time_file,
         coordinates=args.coordinates, product=args.product,
         download=args.download)
