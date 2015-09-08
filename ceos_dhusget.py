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
import requests
from datetime import datetime
from lxml import html

__version__ = "0.1.0"


def dhus_download(prod_tups, download, download_dir, auth):
    """Given list of tuples, download DHuS product or manifest.

    Parameters
    ----------
    prod_tups : list
        List of tuples with titles and URI to download.
    download : string
        String indicating what to download: 'manifest' or 'product'
    download_dir: string
        String indicating path to download directory.
    auth : tuple
        Tuple with user and password to authenticate to DHuS.

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

    for title, uri in prod_tups:

        if download == "manifest":
            dwnld_uri = uri_skel.format(uri, title)
        else:
            dwnld_uri = uri_skel.format(uri)

        fname = os.path.join(download_dir, title + "_manifest_safe")
        uri_conn = requests.get(dwnld_uri, auth=auth, stream=True)
        print "Downloading {0} {1}".format(download, title)
        with open(fname, "w") as dwnf:
            for chunk in uri_conn.iter_content(chunk_size):
                dwnf.write(chunk)
        tstampfn = os.path.join(download_dir, ".last_time_stamp")
        with open(tstampfn, "w") as tstampf:
            tstampf.write(datetime.utcnow().isoformat())


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

    # Prepare search query from criteria requested
    if (time_since is None and time_file is None and
        coordinates is None and product is None):
        qry_statement = "*"
    else:
        qry_statement = ""

        if product is not None:
            qry_statement = "producttype:{}".format(product)

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
            # Now we have a time subquery. Remove possibly empty string
            qry_join = [x for x in [qry_statement, time_subqry] if x]
            qry_statement = " AND ".join(qry_join)

        if coordinates is not None:
            # The polygon string takes the coordinates in the order given
            # in command line
            poly_fstr = ("{0:.13f} {1:.13f}, {2:.13f} {1:.13f}, "
                         "{2:.13f} {3:.13f}, {0:.13f} {3:.13f}, "
                         "{0:.13f} {1:.13f}")
            geo_subqry1 = "(footprint:\"Intersects(POLYGON(("
            geo_subqry2 = poly_fstr.format(coordinates[0], coordinates[1],
                                           coordinates[2], coordinates[3])
            geo_subqry = geo_subqry1 + geo_subqry2 + ")))\")"
            qry_join = [x for x in [qry_statement, geo_subqry] if x]
            qry_statement = " AND ".join(qry_join)

    # The final query URI is ready to be created
    qry_uri = (dhus_uri + "/search?q=" + qry_statement +
               "&rows=10000&start=0")
    dhus_qry = requests.get(qry_uri, auth=(user, password))
    qry_tree = html.fromstring(dhus_qry.content)
    # Retrieve titles and UUIDs from 'title' and 'id' tags under 'entry'
    titles = qry_tree.xpath("//entry/title/text()")
    uuids = qry_tree.xpath("//entry/id/text()")
    # Retrieve product and product root URI from links under entry.  We
    # assume the former doesn't have any 'rel' tag, and the latter has the
    # 'alternative' tag.
    # prod_uris = qry_tree.xpath("//entry//link[not(@rel)]/@href")
    root_uris = qry_tree.xpath("//entry//link[@rel='alternative']/@href")

    prods = zip(titles, root_uris) # we only need these for downloading
    if len(prods) > 0:
        with open("qry_results", "w") as qryfile:
            for tup in zip(titles, uuids, root_uris):
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
    parser.add_argument("dhus-uri",
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
