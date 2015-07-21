#!/bin/bash
#------------------------------------------------------------------------------#
# Demo script illustrating some examples using the OData interface             #
# of the Data Hub Service (DHuS)                                               #
#------------------------------------------------------------------------------#
# Serco SpA 2014                                                               #
#------------------------------------------------------------------------------#
export VERSION=0.1

WD=$HOME/.dhusget
PIDFILE=$WD/pid
LOCK=$WD/lock

test -d $WD || mkdir -p $WD 

#-
mkdir ${LOCK}

if [ ! $? == 0 ]; then 
	echo -e "Error! An istance of \"dhusget\" retriever is running !\n Pid is: "`cat ${PIDFILE}` "if it isn't running delete the lockdir  ${LOCK}"
	exit 
else
	echo $$ > $PIDFILE
fi

trap "rm -fr ${LOCK}" EXIT


function print_usage 
{ 
 echo " "
 echo "---------------------------------------------------------------------------------------------------------------------------"
 echo " "
 echo "This is dhusget $VERSION, a non interactive Sentinel-1 product (or manifest) retriever from a Data Hub instance."
 echo " " 
 echo "Usage: $1 [-d <DHuS URL>] [-u <username> ] [ -p <password>] [-t <time to search (hours)>] [-c <coordinates ie: x1,y1;x2,y2>] [-T <product type>] [-o <option>]"
 echo " "
 echo "---------------------------------------------------------------------------------------------------------------------------"
 echo " "
 echo "-u <username>         : data hub username provided after registration on <DHuS URL> ;"
 echo "-p <password>         : data hub password provided after registration on <DHuS URL> , (note: it's read from stdin, if isn't provided by commandline);"
 echo " "
 echo "-t <time to search (hours)>      : time interval expressed in hours (integer value) from NOW (time of the launch of the "
 echo "                                dhusget) to backwards (e.g. insert the value '24' if you would like to retrieve product "
 echo "                                ingested in the last day);"
 echo ""
 echo " -f <file>                       : A file containg the time of last successfully download"
 echo " "
 echo "-c <coordinates ie: lon1,lat1:lon2,lat2> : coordinates of two opposite vertices of the rectangular area of interest ; "
 echo " "
 echo "-T <product type>                : product type of the product to search (available values are:  SLC, GRD, OCN and RAW) ;"
 echo " "
 echo "-o <option>                      : what to download, possible options are:"
 echo "                                   - 'manifest' to download the manifest of all products returned from the search or "
 echo "                                   - 'product' to download all products returned from the search "
 echo "                                   - 'all' to download both."
 echo "                                		N.B.: if this parameter is left blank, the dhusget will return the UUID and the names "
 echo " 			      					 of the products found in the DHuS archive."
 echo " "
 echo "'wget' is necessary to run the dhusget"
 echo " " 

 exit -1
}

#----------------------
#---  Load input parameter
export DHUS_DEST="https://dhus.example.com"
export USERNAME="test"
#export PASSWORD="test"
export TIME_SUBQUERY=""
export PRODUCT_TYPE='*'

unset TIMEFILE


while getopts ":d:u:p:t:f:c:T:o:" opt; do
 case $opt in
	d)
		export DHUS_DEST="$OPTARG"
		;;
	u)
		export USERNAME="$OPTARG"
		;;
	p)
		export PASSWORD="$OPTARG"
		;;
	t)
		export TIME="$OPTARG"
		export TIME_SUBQUERY="ingestiondate:[NOW-${TIME}HOURS TO NOW] AND "
		;;	
	f)
		export TIMEFILE="$OPTARG"
		if [ -f $TIMEFILE ]; then 		
			export TIME_SUBQUERY="ingestiondate:[`cat $TIMEFILE` TO NOW] AND "
		else
			export TIME_SUBQUERY="ingestiondate:[1970-01-01T00:00:00.000Z TO NOW] AND "
		fi
		;;
	c) 
		ROW=$OPTARG

		FIRST=`echo "$ROW" | awk -F\: '{print \$1}' `
		SECOND=`echo "$ROW" | awk -F\: '{print \$2}' `

		#--
		export x1=`echo ${FIRST}|awk -F, '{print $1}'`
		export y1=`echo ${FIRST}|awk -F, '{print $2}'`
		export x2=`echo ${SECOND}|awk -F, '{print $1}'`
		export y2=`echo ${SECOND}|awk -F, '{print $2}'`
		;;

	T)
		export PRODUCT_TYPE="$OPTARG"
		;;
	o)
		export TO_DOWNLOAD="$OPTARG"
		;;
	*)	
		 print_usage $0
		;;		
	 esac
done

if [ -z $PASSWORD ];then
	read -s -p "Enter password ..." VAL
	export PASSWORD=${VAL}
fi

#-----
export WC="wget --no-check-certificate"
#--ca-certificate=/etc/pki/CA/certs/ca.cert.pem"
export AUTH="--user=${USERNAME} --password=${PASSWORD}"


#--- Prepare query statement
export QUERY_STATEMENT="${DHUS_DEST}/search?q=${TIME_SUBQUERY}producttype:${PRODUCT_TYPE}"
#export QUERY_STATEMENT="${DHUS_DEST}/search?q=ingestiondate:[NOW-${TIME}DAYS TO NOW] AND producttype:${PRODUCT_TYPE}"

#--- 
#export QUERY_STATEMENT=`echo "${QUERY_STATEMENT}"|sed 's/ /+/g'`

#---- Prepare query polygon statement
if [ ! -z $x1 ];then
	export GEO_SUBQUERY=`LC_NUMERIC=en_US.UTF-8; printf "AND+( footprint:\"Intersects(POLYGON((%.13f %.13f,%.13f %.13f,%.13f %.13f,%.13f %.13f,%.13f %.13f )))\")" $x1 $y1 $x2 $y1 $x2 $y2 $x1 $y2 $x1 $y1 `
else
	export GEO_SUBQUERY=""
fi

#- ... append on query (without repl
export QUERY_STATEMENT=${QUERY_STATEMENT}"+${GEO_SUBQUERY}&rows=10000&start=0"

#--- Select output format
#export QUERY_STATEMENT+="&format=json"

#--- Execute query statement
/bin/rm -f query-result
mkdir -p ./output/
set -x
${WC} ${AUTH} --output-file=./output/.log_query.log -O query-result "${QUERY_STATEMENT}"
set +x
LASTDATE=`date -u +%Y-%m-%dT%H:%M:%S.%NZ`
sleep 5

echo ""
cat $PWD/query-result | grep '<id>' | tail -n +2 | cut -f2 -d'>' | cut -f1 -d'<' | cat -n > .product_id_list
cat $PWD/query-result | grep '<title>' | tail -n +2 | cut -f2 -d'>' | cut -f1 -d'<' | cat -n > .product_title_list
##cat $PWD/query-result | xmlstarlet sel -T -t -m '/_:feed/_:entry/_:title/text()' -v '.' -n | cat -n | tee  .product_title_list

cat .product_id_list .product_title_list | sort -nk 1 | sed 's/[",:]/ /g' > product_list

rm -f .product_id_list .product_title_list

echo ""
NROW=`cat product_list |wc -l`
NPRODUCT=`echo ${NROW}/2 | bc -q `


echo -e "done... product_list contain results \n ${NPRODUCT} products"

echo ""

cat product_list
export rv=0
if [ "${TO_DOWNLOAD}" == "manifest" -o "${TO_DOWNLOAD}" == "all" ]; then
	#if [ -z $9 ] ; then
	export INPUT_FILE=product_list
#	else
	#export INPUT_FILE=$9
#	fi

	if [ ! -f ${INPUT_FILE} ]; then
	 echo "Error: Input file ${INPUT_FILE} not present "
	 exit
	fi

	mkdir -p MANIFEST/

	#--- Parsing input file
	cat ${INPUT_FILE} |  while read line ; do 
	UUID=`echo $line | awk '{print $2}'`
	read line 
	PRODUCT_NAME=`echo $line | awk '{print $2}'`

#	set -x
echo 	  ${WC} ${AUTH} --output-file=./output/.log.${PRODUCT_NAME}.log -O ./MANIFEST/manifest.safe-${PRODUCT_NAME} "${DHUS_DEST}/odata/v1/Products('${UUID}')/Nodes('${PRODUCT_NAME}.SAFE')/Nodes('manifest.safe')/\$value"
	  ${WC} ${AUTH} --output-file=./output/.log.${PRODUCT_NAME}.log -O ./MANIFEST/manifest.safe-${PRODUCT_NAME} "${DHUS_DEST}/odata/v1/Products('${UUID}')/Nodes('${PRODUCT_NAME}.SAFE')/Nodes('manifest.safe')/\$value"
	r=$?
	let rv=$rv+$r
#	set +x

	done
fi

if [ "${TO_DOWNLOAD}" == "product" -o "${TO_DOWNLOAD}" == "all" ];then
#	if [ -z $9 ] ; then
        export INPUT_FILE=product_list
#        else
#        export INPUT_FILE=$9
#        fi

	mkdir -p PRODUCT/

	#--- Parsing input file
	cat ${INPUT_FILE} |  while read line ; do 
	UUID=`echo $line | awk '{print $2}'`
	read line 
	PRODUCT_NAME=`echo $line | awk '{print $2}'`
#	set -x
echo 	${WC} ${AUTH} --output-file=./output/.log.${PRODUCT_NAME}.log -O ./PRODUCT/${PRODUCT_NAME} "${DHUS_DEST}/odata/v1/Products('${UUID}')/\$value"
	${WC} ${AUTH} --output-file=./output/.log.${PRODUCT_NAME}.log -O ./PRODUCT/${PRODUCT_NAME} "${DHUS_DEST}/odata/v1/Products('${UUID}')/\$value"
	r=$?
	let rv=$rv+$r
#	set +x
	done
fi

if [ $rv == 0 ]; then
	if [ ! -z $TIMEFILE ]; then
		echo "$LASTDATE" > $TIMEFILE
	fi
fi
	

