#! /bin/bash
# Author: Sebastian Luque
# Created: 2015-09-01T22:30:39+0000
# Last-Updated: 2015-09-03T13:37:51+0000
#           By: Sebastian P. Luque
# -------------------------------------------------------------------------
# Commentary:
#
# This is a fully functional adaptation of dhusget.sh demo from Sentinel's
# Batch scripting guide from their web site.
#
# Example:
#
# ./ceos_dhusget.sh -u USER -p SECRET -T SLC -d https://scihub.esa.int/dhus
# -------------------------------------------------------------------------
# Code:

version=0.1.0

wd=${HOME}/.dhusget
pidfile=${wd}/pid
lock=${wd}/lock
test -d ${wd} || mkdir -p ${wd}
mkdir ${lock}

if [ ! $? == 0 ]; then
    echo "Error! An istance of \"dhusget\" retriever is running!"
    echo "pid is: $(cat ${pidfile})"
    echo "If it isn't running delete the lock directory: ${lock}"
    exit
else
    echo $$ > $pidfile
fi
trap "rm -rf ${lock}" EXIT

usage() {
    cat <<EOF
DESCRIPTION
    This is dhusget $version, a non interactive Sentinel-1 product (or manifest)
    retriever from a Data Hub instance.

USAGE
    $1 [-u <username> ] [ -p <password>] [-t <time to search (hours)>]
       [-c <coordinates ie: x1,y1;x2,y2>] [-T <product type>] [-o <option>]
       DHuS_URL

OPTIONS
    -u <username>:
        Data hub username provided after registration on <DHuS URL>

    -p <password>:
        Data hub password provided after registration on <DHuS URL>
        (note: it's read from stdin, if isn't provided by commandline)

    -t <time to search (hours)>:
        Time interval expressed in hours (integer value) from NOW
        (time of the launch of the dhusget) to backwards
        (e.g. insert the value '24' if you would like to retrieve product
        ingested in the last day)

     -f <file>:
        A file containg the time of last successfully download

     -c <coordinates ie: lon1,lat1:lon2,lat2>:
        Coordinates of two opposite vertices of the rectangular area of
        interest.

     -T <product type>:
        Product type of the product to search
        (available values are: SLC, GRD, OCN, S2MSI1C)

     -o <option>:
        What to download, possible options are:
        - 'manifest' to download the manifest of all products returned
          from the search
        - 'product' to download all products returned from the search
        - 'all' to download both.
        N.B.: if this parameter is left blank, the dhusget will return
        the UUID and the names of the products found in the DHuS archive.

NOTE
     'wget' executable must be available on PATH.

EOF
}

print_version() {
    echo "ceos_dhusget ${version}"
    exit -1
}

#---  Load input parameter
dhus_dest="https://dhus.example.com"
username=""
password=""
time_subquery=""
product_type=""

unset timefile
while getopts ":u:p:t:f:c:T:o:vh" opt; do
    case $opt in
	u)
	    username="${OPTARG}"
	    ;;
	p)
	    password="${OPTARG}"
	    ;;
	t)
	    time="${OPTARG}"
	    time_subquery="ingestiondate:[NOW-${time}HOURS TO NOW]"
	    ;;
	f)
	    timefile="${OPTARG}"
	    if [ -f "$timefile" ]; then
		TIME_SUBQUERY="ingestiondate:[$(cat $timefile) TO NOW]"
	    else
		TIME_SUBQUERY="ingestiondate:[1970-01-01T00:00:00.000Z TO NOW]"
	    fi
	    ;;
	c)
	    row=${OPTARG}
	    first=$(echo "$row" | awk -F: '{print $1}')
	    second=$(echo "$row" | awk -F: '{print $2}')
	    x1=$(echo ${first} | awk -F, '{print $1}')
	    y1=$(echo ${first} | awk -F, '{print $2}')
	    x2=$(echo ${second} | awk -F, '{print $1}')
	    y2=$(echo ${second} | awk -F, '{print $2}')
	    ;;

	T)
	    product_type="${OPTARG}"
	    ;;
	o)
	    to_download="${OPTARG}"
	    ;;
	v)
	    print_version $0
	    ;;
	h)
	    usage $0
	    ;;
	*)
	    echo "Unrecognized option"
	    usage $0
	    exit -1
    esac
done
shift $(( $OPTIND - 1 ))

# Sanity checks
if [ "$#" != 1 ]; then
    echo "One DHuS URL is required."
    usage $0
    exit 1
fi

if [ -z "$password" ]; then
    read -s -p "Enter password ..." val
    password=${val}
fi

dhus_dest=$1
wc="wget --no-check-certificate"
auth="--user=${username} --password=${password}"

# If we haven't gotten any period to search for, nor coordinates or product
# type, then set a wildcard query statement
if [ -z "${time}" ] && [ -z "${timefile}" ] && \
       [ -z "${row}" ] && [ -z "${product_type}" ]; then
    query_statement="*"
fi

# First check if we were asked for a product type, and if so, append
# producctype request to query statement
if [ ! -z "${product_type}" ]; then
    query_statement="producttype:$product_type"
fi

# If we were asked for a period, append the corresponding time subquery to
# the query statement
if [ ! -z "${time}" ]; then
    if [ ! -z "${query_statement}" ]; then
	query_statement="${query_statement} AND ${time_subquery}"
    else
	query_statement="${time_subquery}"
    fi
fi

# Prepare query polygon statement
if [ ! -z $x1 ]; then
    geo_subq1="(footprint:\"Intersects(POLYGON(("
    geo_subq2="%.13f %.13f,%.13f %.13f,%.13f %.13f,%.13f %.13f,%.13f %.13f"
    geo_subq="${geo_subq1}${geo_subq2})))\")"
    geo_subquery=$(printf "${geo_subq}" $x1 $y1 $x2 $y1 $x2 $y2 $x1 $y2 \
    			  $x1 $y1)
    if [ ! -z "${query_statement}" ]; then
	query_statement="${query_statement} AND ${geo_subquery}"
    else
	query_statement="${geo_subquery}"
    fi
fi

query_uri="${dhus_dest}/search?q=${query_statement}&rows=10000&start=0"
query_file=query_result
products_list_file=product_list

# Execute query statement create our list of products
rm -f ${query_file} ${products_list_file}
mkdir -p ./output/
echo "Requesting ${query_uri}"
${wc} ${auth} --output-file=./output/.log_query.log \
      -O "${query_file}" "${query_uri}"
lastdate=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
sleep 5

# I think all this xml scraping would be better done in Python.  However,
# the downloading seems better/easier with wget... perhaps the requests,
# lxml, and subprocess modules is all we'd need?
awk -v fn="${products_list_file}" '
    /<title>/ {			# This rule needs to be 1st
        split($0, title_arr, /[<>]/)
        title=title_arr[3] # 1st position is empty, so need 3rd
        if (title ~ /results for/) next
        print ++nrow, title > fn
    }
    /<id>/ {
        split($0, id_arr, /[<>]/)
        id=id_arr[3] # 1st position is empty, so need 3rd
        if (id ~ /\/+/) next
        print nrow, id >> fn
    }
' ${query_file}

if [ ! -f ${products_list_file} ]; then
    echo "Error: Input file ${products_list_file} not generated"
    exit
fi

# Now we're ready to download what we requested, if any

dhus_download() { #@ USAGE: download PROD_FILE OPT ('-m' or '-p')
    # There's only two options, so for now we just test for -m
    if [ $2 == "-m" ]; then
	mkdir -p MANIFEST
    else
	mkdir -p PRODUCT
    fi
    local rv=0
    while read line ; do
	product_name=$(echo $line | awk '{print $2}')
	read line
	uuid=$(echo $line | awk '{print $2}')
	if [ $2 == "-m" ]; then
	    url_str1="${dhus_dest}/odata/v1/Products('${uuid}')/Nodes"
	    url_str2="('${product_name}.SAFE')/Nodes('manifest.safe')"
	    url_str="${url_str1}${url_str2}/\$value"
	    echo "Downloading ${url_str}"
	    ${wc} ${auth} --output-file=./output/.log.${product_name}.log \
		  -O ./MANIFEST/manifest.safe-${product_name} "${url_str}"
	    r=$?
	    let rv=$rv+$r
	else
	    url_str="${dhus_dest}/odata/v1/Products('${uuid}')/\$value"
	    echo "Downloading ${URL_STR}"
	    ${wc} ${auth} --output-file=./output/.log.${product_name}.log \
		  -O ./PRODUCT/${product_name}".zip" "${url_str}"
	    r=$?
	    let rv=$rv+$r
	fi
    done < $1
    if [ $rv == 0 ]; then
	if [ ! -z "$timefile" ]; then
	    echo "$lastdate" > $timefile
	fi
    fi
}

if [ -z ${to_download} ]; then
    echo "No downloads requested; query results written to ${query_file}"
    exit
elif [ "${to_download}" == "manifest" -o "${to_download}" == "all" ]; then
    dhus_download ${products_list_file} "-m"
elif [ "${to_download}" == "product" -o "${to_download}" == "all" ]; then
    dhus_download ${products_list_file} "-p"
fi
