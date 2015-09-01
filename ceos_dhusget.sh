#! /bin/bash
# Author: Sebastian Luque
# Created: 2015-09-01T22:30:39+0000
# Last-Updated: 2015-09-01T22:35:48+0000
#           By: Sebastian Luque
# -------------------------------------------------------------------------
# Commentary:
#
# This is a re-written version of dhusget demo from the Sentinel's Batch
# scripting guide.
# -------------------------------------------------------------------------
# Code:

VERSION=0.3

WD=${HOME}/.dhusget
PIDFILE=${WD}/pid
LOCK=${WD}/lock

test -d ${WD} || mkdir -p ${WD}

mkdir ${LOCK}

if [ ! $? == 0 ]; then
    echo "Error! An istance of \"dhusget\" retriever is running !"
    echo "Pid is: $(cat ${PIDFILE})"
    echo "If it isn't running delete the lockdir ${LOCK}"
    exit
else
    echo $$ > $PIDFILE
fi
trap "rm -rf ${LOCK}" EXIT


usage () {
    cat <<EOF
DESCRIPTION

    This is dhusget $VERSION, a non interactive Sentinel-1 product
    (or manifest) retriever from a Data Hub instance.

USAGE
    $1 [-d <DHuS URL>] [-u <username> ] [ -p <password>]
       [-t <time to search (hours)>] [-c <coordinates ie: x1,y1;x2,y2>]
       [-T <product type>] [-o <option>]

OPTIONS
    -d <DHuS URL>:
        The URL of the Data Hub to query

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
        (available values are:  SLC, GRD, OCN and RAW)

     -o <option>:
        What to download, possible options are:
        - 'manifest' to download the manifest of all products returned
          from the search
        - 'product' to download all products returned from the search
        - 'all' to download both.
        N.B.: if this parameter is left blank, the dhusget will return
        the UUID and the names of the products found in the DHuS archive.

NOTE
     'wget' is necessary to run the dhusget

EOF
}

print_version () {
    echo "dhusget ${VERSION}"
    exit -1
}

#---  Load input parameter
DHUS_DEST="https://dhus.example.com"
USERNAME=""
PASSWORD=""
TIME_SUBQUERY=""
PRODUCT_TYPE=""

unset TIMEFILE

while getopts ":d:u:p:t:f:c:T:o:V" opt; do
    case $opt in
	d)
	    DHUS_DEST="${OPTARG}"
	    ;;
	u)
	    USERNAME="${OPTARG}"
	    ;;
	p)
	    PASSWORD="${OPTARG}"
	    ;;
	t)
	    TIME="${OPTARG}"
	    TIME_SUBQUERY="ingestiondate:[NOW-${TIME}HOURS TO NOW]"
	    ;;
	f)
	    TIMEFILE="${OPTARG}"
	    if [ -f "$TIMEFILE" ]; then
		TIME_SUBQUERY="ingestiondate:[$(cat $TIMEFILE) TO NOW]"
	    else
		TIME_SUBQUERY="ingestiondate:[1970-01-01T00:00:00.000Z TO NOW]"
	    fi
	    ;;
	c)
	    ROW=${OPTARG}
	    FIRST=$(echo "$ROW" | awk -F: '{print $1}')
	    SECOND=$(echo "$ROW" | awk -F: '{print $2}')
	    x1=$(echo ${FIRST} | awk -F, '{print $1}')
	    y1=$(echo ${FIRST} | awk -F, '{print $2}')
	    x2=$(echo ${SECOND} | awk -F, '{print $1}')
	    y2=$(echo ${SECOND} | awk -F, '{print $2}')
	    ;;

	T)
	    PRODUCT_TYPE="${OPTARG}"
	    ;;
	o)
	    TO_DOWNLOAD="${OPTARG}"
	    ;;
	V)
	    print_version $0
	    ;;
	*)
	    echo "Unrecognized option"
	    usage $0
	    exit -1
    esac
done

if [ -z "$PASSWORD" ]; then
    read -s -p "Enter password ..." VAL
    PASSWORD=${VAL}
fi

WC="wget --no-check-certificate"
AUTH="--user=${USERNAME} --password=${PASSWORD}"

# If we haven't gotten any period to search for, nor coordinates or product
# type, then set a wildcard query statement
if [ -z "${TIME}" ] && [ -z "${TIMEFILE}" ] && \
       [ -z "${ROW}" ] && [ -z "${PRODUCT_TYPE}" ]; then
    QUERY_STATEMENT="*"
fi

# First check if we were asked for a product type, and if so, append
# producctype request to query statement
if [ ! -z "${PRODUCT_TYPE}" ]; then
    QUERY_STATEMENT="producttype:$PRODUCT_TYPE"
fi

# If we were asked for a period, append the corresponding time subquery to
# the query statement
if [ ! -z "${TIME}" ]; then
    if [ ! -z "${QUERY_STATEMENT}" ]; then
	QUERY_STATEMENT="${QUERY_STATEMENT} AND"
    fi
    QUERY_STATEMENT="${QUERY_STATEMENT} ${TIME_SUBQUERY}"
fi

#---- Prepare query polygon statement
if [ ! -z $x1 ]; then
    if [ ! -z "${QUERY_STATEMENT}" ]; then
	QUERY_STATEMENT="${QUERY_STATEMENT} AND"
    fi
    geo_subq1="(footprint:\"Intersects(POLYGON(("
    geo_subq2="%.13f %.13f,%.13f %.13f,%.13f %.13f,%.13f %.13f,%.13f %.13f"
    geo_subq="${geo_subq1}${geo_subq2})))\")"
    GEO_SUBQUERY=$(printf "${geo_subq}" $x1 $y1 $x2 $y1 $x2 $y2 $x1 $y2 \
    			  $x1 $y1)
    QUERY_STATEMENT="${QUERY_STATEMENT} ${GEO_SUBQUERY}"
fi

QUERY_STATEMENT="${DHUS_DEST}/search?q=${QUERY_STATEMENT}&rows=10000&start=0"

#--- Execute query statement create our list of products
rm -f query-result
mkdir -p ./output/
echo "Requesting ${QUERY_STATEMENT}"
${WC} ${AUTH} --output-file=./output/.log_query.log \
      -O query-result "${QUERY_STATEMENT}"
LASTDATE=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
sleep 5

awk -v ofile="${PRODUCTS_LIST_FILE}" '
    /<title>/ {			# This rule needs to be 1st
        split($0, title_arr, /[<>]/)
        title=title_arr[3] # 1st position is empty, so need 3rd
        if (title ~ /results for/) next
        print ++nrow, title > "product_list"
    }
    /<id>/ {
        split($0, id_arr, /[<>]/)
        id=id_arr[3] # 1st position is empty, so need 3rd
        if (id ~ /\/+/) next
        print nrow, id >> "product_list"
    }
' query-result

PRODUCTS_LIST_FILE=product_list
if [ ! -f ${PRODUCTS_LIST_FILE} ]; then
    echo "Error: Input file ${PRODUCTS_LIST_FILE} not found"
    exit
fi

# Now we're ready to download what we requested
rv=0
if [ "${TO_DOWNLOAD}" == "manifest" -o "${TO_DOWNLOAD}" == "all" ]; then
    mkdir -p MANIFEST/
    while read line ; do
	PRODUCT_NAME=$(echo $line | awk '{print $2}')
	read line
	UUID=$(echo $line | awk '{print $2}')
	URL_STR1="${DHUS_DEST}/odata/v1/Products('${UUID}')/Nodes"
	URL_STR2="${URL_STR1}('${PRODUCT_NAME}.SAFE')/Nodes('manifest.safe')"
	URL_STR="${URL_STR2}/\$value"
	echo ${URL_STR}
	${WC} ${AUTH} --output-file=./output/.log.${PRODUCT_NAME}.log \
	      -O ./MANIFEST/manifest.safe-${PRODUCT_NAME} "${URL_STR}"
	r=$?
	let rv=$rv+$r
    done < ${PRODUCTS_LIST_FILE}
fi

if [ "${TO_DOWNLOAD}" == "product" -o "${TO_DOWNLOAD}" == "all" ]; then
    mkdir -p PRODUCT/
    while read line ; do
	PRODUCT_NAME=$(echo $line | awk '{print $2}')
	read line
	UUID=$(echo $line | awk '{print $2}')
	URL_STR="${DHUS_DEST}/odata/v1/Products('${UUID}')/\$value"
	echo ${URL_STR}
	${WC} ${AUTH} --output-file=./output/.log.${PRODUCT_NAME}.log \
	      -O ./PRODUCT/${PRODUCT_NAME}".zip" "${URL_STR}"
	r=$?
	let rv=$rv+$r
    done < ${PRODUCTS_LIST_FILE}
fi

if [ $rv == 0 ]; then
    if [ ! -z $TIMEFILE ]; then
	echo "$LASTDATE" > $TIMEFILE
    fi
fi
