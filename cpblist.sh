#!/bin/bash

################################################
# Author: Francesco Ficarola
# Website: www.francescoficarola.com
# Blog Post: https://www.francescoficarola.com/check-point-automated-ip-blacklist
# Inspired by: OpenDBL (http://www.opendbl.net/)
##################################################

# Import VSX environment
if [[ -e /etc/profile.d/CP.sh ]]; then source /etc/profile.d/CP.sh; fi
if [[ -e /etc/profile.d/vsenv.sh ]]; then source /etc/profile.d/vsenv.sh; fi

# Change the number with your Virtual System ID
VSID=1

# Context variables
CONTEXT="ContextName"
SCRIPT_PATH="/scripts/blacklist"
OBJ_NAME="BLDO_${CONTEXT}"
OBJ_NAME_TMP="${OBJ_NAME}_tmp"
FEED_PATH="${SCRIPT_PATH}/feeds"
FEED="${FEED_PATH}/${CONTEXT}.feed"
LOG_PATH="${SCRIPT_PATH}/logs"
LOG="${LOG_PATH}/${CONTEXT}.log"
TMP_PATH="${SCRIPT_PATH}/tmp"
OBJ_FILE="${TMP_PATH}/${CONTEXT}.obj"
OBJ_TMP_FILE="${TMP_PATH}/${CONTEXT}_tmp.obj"
ADD_FILE="${TMP_PATH}/${CONTEXT}.add"
DEL_FILE="${TMP_PATH}/${CONTEXT}.del"
HOSTNAME=$(hostname)

# Blacklist Feeds
URL[0]="..."
URL[1]="..."
URL[2]="..."

# Regular expression variables
INPUT_PATTERN='^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\/([89]|[12][0-9]|3[0-2]))?)$'
CIDR_REGEX='^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\/([89]|[12][0-9]|3[0-2])){1,})$'
IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]))$'

# Counting variables
N_ELEM_PER_ITEM=2000
x_tmp=0
y_tmp=0
x_del=0
y_del=0
x_add=0
y_add=0

# Creating directories
[ -d $FEED_PATH ] || mkdir -p $FEED_PATH
[ -d $LOG_PATH ] || mkdir -p $LOG_PATH
[ -d $TMP_PATH ] || mkdir -p $TMP_PATH

# Init log file
>> $LOG

# Init feed file
> $FEED

# Convert function
function convert {
	# Creating the object if not exists
	if [[ $(dynamic_objects -l | grep -Po " : ${OBJ_NAME}$" | wc -l) == 0 ]]; then
		echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Creating new ${OBJ_NAME} object..." | tee -a $LOG
		dynamic_objects -n $OBJ_NAME
	fi

	# Reading the feed
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Reading feed lines and saving IPs and Networks to array..." | tee -a $LOG
	while read line; do
		if [[ $line =~ $IP_REGEX ]]; then
			ip=$line

			todo[$x_tmp]+=" $ip $ip"
			if [ $y_tmp -eq $N_ELEM_PER_ITEM ]
			then
				y_tmp=0
				let x_tmp=$x_tmp+1
			else
				let y_tmp=$y_tmp+1
			fi
		elif [[ $line =~ $CIDR_REGEX ]]; then
			net=$line
			ip_net=$(ipcalc -n $net | sed -re 's/NETWORK=//')
			ip_broad=$(ipcalc -b $net | sed -re 's/BROADCAST=//')

			todo[$x_tmp]+=" $ip_net $ip_broad"
			if [ $y_tmp -eq $N_ELEM_PER_ITEM ]
			then
				y_tmp=0
				let x_tmp=$x_tmp+1
			else
				let y_tmp=$y_tmp+1
			fi
		fi
	done

	# Creating the temporary object
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Creating new ${OBJ_NAME_TMP} object..." | tee -a $LOG
	dynamic_objects -n $OBJ_NAME_TMP

	# Populating the temporary object
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Populating the ${OBJ_NAME_TMP} object..." | tee -a $LOG
	for i in "${todo[@]}"; do
		dynamic_objects -o $OBJ_NAME_TMP -r $i -a
	done

	# Exporting the current object to file
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Saving the ${OBJ_NAME} object to temporary file ${OBJ_FILE}..." | tee -a $LOG
	dynamic_objects -l | sed -n -r '/'"${CONTEXT}"'$/,/^$/{//!p;}' | sed -r -e 's/range [0-9]+ \: //g'  > ${OBJ_FILE}

	# Exporting the new temporary object to file
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Saving the ${OBJ_NAME_TMP} object to temporary file ${OBJ_TMP_FILE}..." | tee -a $LOG
	dynamic_objects -l | sed -n -r '/'"${CONTEXT}"'_tmp$/,/^$/{//!p;}' | sed -r -e 's/range [0-9]+ \: //g'  > ${OBJ_TMP_FILE}

	# Diff between current object and new temporary object
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Diff between ${OBJ_FILE} and ${OBJ_TMP_FILE} files..." | tee -a $LOG
	diff ${OBJ_FILE} ${OBJ_TMP_FILE} | grep -Po "< \d+\.\d+\.\d+\.\d+\s+\d+\.\d+\.\d+\.\d+" | sed -e 's/< //g' > ${DEL_FILE}
	diff ${OBJ_FILE} ${OBJ_TMP_FILE} | grep -Po "> \d+\.\d+\.\d+\.\d+\s+\d+\.\d+\.\d+\.\d+" | sed -e 's/> //g' > ${ADD_FILE}

	# Deleting obsolete ranges
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Checking if there are ranges to be deleted..." | tee -a $LOG
	if [ -s $DEL_FILE ]; then
		echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Reading ranges to be deleted..." | tee -a $LOG
		while read range; do
			todel[$x_del]+=" $range"
			if [ $y_del -eq $N_ELEM_PER_ITEM ]
			then
				y_del=0
				let x_del=$x_del+1
			else
				let y_del=$y_del+1
			fi
		done < $DEL_FILE

		echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Deleting obsolete ranges from the ${OBJ_NAME} object..." | tee -a $LOG
		for i in "${todel[@]}"; do
			dynamic_objects -o $OBJ_NAME -r $i -d
		done
	else
		echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - No range to be deleted!" | tee -a $LOG
	fi

	# Adding new ranges
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Checking if there are ranges to be added..." | tee -a $LOG
	if [ -s $ADD_FILE ]; then
		echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Reading ranges to be added..." | tee -a $LOG
		while read range; do
			toadd[$x_add]+=" $range"
			if [ $y_add -eq $N_ELEM_PER_ITEM ]
			then
				y_add=0
				let x_add=$x_add+1
			else
				let y_add=$y_add+1
			fi
		done < $ADD_FILE

		echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Adding new ranges from the ${OBJ_NAME} object..." | tee -a $LOG
		for i in "${toadd[@]}"; do
			dynamic_objects -o $OBJ_NAME -r $i -a
		done
	else
		echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - No range to be added!" | tee -a $LOG
	fi

	# Deleting the temporary object
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Deleting the temporary ${OBJ_NAME_TMP} object..." | tee -a $LOG
	dynamic_objects -do $OBJ_NAME_TMP

	# Deleting all temporary files
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Deleting temporary files..." | tee -a $LOG
	rm ${TMP_PATH}/*

	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Done!" | tee -a $LOG
}

# Process function
function process {
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Removing duplicates and sorting..." | tee -a $LOG
	awk '!seen[$0]++' $FEED > ${FEED}.tmp
	sort -n ${FEED}.tmp -o $FEED
	rm ${FEED}.tmp

	cat $FEED | convert
}

# Fetching the feeds
for i in "${URL[@]}"; do
	echo "[$(date +'%d-%m-%Y %H:%M:%S')] ${CONTEXT} ${HOSTNAME} - Fetching the following feed: ${i}" | tee -a $LOG
	curl_cli --insecure --retry 10 --retry-delay 60 $i | dos2unix | grep -Po $INPUT_PATTERN >> $FEED
done

# Switch to the correct VS
vsenv $VSID

# Call the process function
process
