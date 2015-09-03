#! /usr/bin/env python

import requests
import lxml
import subprocess

__version__ = "0.1.0"

def main(dhus_uri, user, password, time_since=None, time_file=None,
         coordinates=None, product=None, download=None):
    """Query, and optionally, download products from DHuS Data Hub.

    See parser help for description of arguments.  All arguments are coerced to
    string during execution.

    """
    if (time_since is None and time_file is None and
        coordinates is None and product is None):
        qry_statement = "*"
    else:
        qry_statement = ""
        if product is not None:
            qry_statement = "producttype:{}".format(product)

        if time_since is not None or time_file is not None:
            time_str = "ingestiondate:[NOW-{}HOURS TO NOW"
            if time_since is not None: # overrides time_file
                time_subqry = time_str.format(time_since)
            else:               # we have time_file
                try:
                    with open(time_file) as tfile:
                        time_infile = tfile.readline().strip()
                        time_subqry = time_subqry.format(time_infile)
                except IOError as err:
                    print "I/O error ({0}): {1}".format(err.errno,
                                                        err.strerror)
                except:
                    dflt_last = "1970-01-01T00:00:00.000Z"
                    time_subqry = time_subquery.format(dflt_last)
                    print "Unexpected error; assuming {}".format(dflt_last)
            # Now we have a time subquery
            qry_join = filter(None, [qry_statement, time_subqry])
            qry_statement = " AND ".join(qry_join)

        if coordinates is not None:
            geo_subqry1 = "(footprint:\"Intersects(POLYGON(("
            geo_subqry2 = ("{0:.13f} {1:.13f}, {2:.13f} {1:.13f}," +
                           "{2:.13f} {3:.13f}, {0:.13f} {3:.13f}," +
                           "{0:.13f} {1:.13f}").format(coordinates[0],
                                                       coordinates[1],
                                                       coordinates[2],
                                                       coordinates[3])
            geo_subqry = geo_subqry1 + geo_subqry2 + ")))\")"
            qry_join = filter(None, [qry_statement, geo_subqry])
            

if __name__ == "__main__":
    import argparse
    _DESCRIPTION = """
    Non-interactive Sentinel-1 product (or manifest) retriever from a Data Hub
    instance."""
    parser = argparse.ArgumentParser(description=_DESCRIPTION)
    parser.add_argument("dhus_uri",
                        help="DHuS root URI, without trailing slash ('/').")
    parser.add_argument("-u", "--user", required=True,
                        help="Registered Data Hub user name.")
    parser.add_argument("-p", "--password", required=True,
                        help="Password for registered Data Hub user.")
    parser.add_argument("-t", "--time_since", type=int,
                        help=("Number of hours (integer) since the time " +
                              "the request is made to search for products"))
    parser.add_argument("-f", "--time_file", type=argparse.FileType("r+"),
                        help=("Path to file containing the time of last " +
                              "successful download."))
    parser.add_argument("-c", "--coordinates", metavar="COORD",
                        nargs=4, type=float,
                        help=("Geographical coordinates of two opposite " +
                              "vertices of rectangular area to search for " +
                              "(lon1 lat1 lon2 lat2)"))
    parser.add_argument("-T", "--product",
                        choices=["SLC", "GRD", "OCN", "S2MSI1C"],
                        help="Product type to search.")
    parser.add_argument("-d", "--download",
                        choices=["manifest", "product", "all"],
                        help=("What to download. If not prodived, only " +
                              "UUID and product names are downloaded."))
    parser.add_argument("--version", action="version",
                        version="%(prog)s {}".format(__version__))
    args = parser.parse_args()
    main(dhus_uri=args.dhus_uri, user=args.user, password=args.password,
         time_since=args.time_since, time_file=args.time_file,
         coordinates=args.coordinates, product=args.product,
         download=args.download)
