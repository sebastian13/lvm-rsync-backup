#!/bin/bash

__VERBOSE=7

declare -A LOG_LEVELS
# https://en.wikipedia.org/wiki/Syslog#Severity_level
LOG_LEVELS=([0]="emerg" [1]="alert" [2]="crit" [3]="err" [4]="warning" [5]="notice" [6]="info" [7]="debug")
function .log () {
local LEVEL=${1}
shift
if [ ${__VERBOSE} -ge ${LEVEL} ]; then
echo "[${LOG_LEVELS[$LEVEL]}]" "$@" >> backup.log 1>&2
fi
}

MYDIR="$(dirname "$(readlink -f "$0")")"

function clean {
	.log 7 "clean ()"
	.log 6 "LV to delete        | $DELETE_LV"

	SNAPSHOT_MOUNT="/mnt/${DELETE_LV}"
	.log 6 "Snapshot Mountpoint | $SNAPSHOT_MOUNT"

	# If the snapshot mountpoint still exists try unmounting and removing it
	#
	if [ -d ${SNAPSHOT_MOUNT} ] ; then
	umount ${SNAPSHOT_MOUNT}
	rmdir ${SNAPSHOT_MOUNT}
	fi

	DELETE_PATH=$(lvs --noheading -o lv_path | grep -P "${DELETE_LV}( |$)" | tr -d '  ')
	.log 6 "Delete Path         | $DELETE_PATH"

	# If the snapshot logical volume still exists, remove it
	#
	lvs -o lv_name | grep -e "\s${DELETE_LV}\s" 
	if [ $? = 0 ]; then
		.log 6 "Will remove ${DELETE_LV} in 10 seconds!"
		sleep 10
		lvremove -f ${DELETE_PATH}
	fi
}

function clean-all {
	.log 7 "clean-all ()"
	for DELETE_LV in $(lvs --noheading -o lv_name | grep -e 'snapshot' | tr -d '  ')
	do
		clean
	done
}

function backup {
	.log 7 "backup ()"
	.log 6 "LV to backup        | $BACKUP_LV"

	# Remove Tailing Slash, if there is one.
	length=${#DESTINATION}
	last_char=${DESTINATION:length-1:1}
	[[ $last_char == "/" ]] && DESTINATION=${DESTINATION:0:length-1}; 
	.log 6 "Destination Mount   | $DESTINATION"

	BUFFER_SIZE=10G

	count=$(lvs --noheading -o lv_name | grep -cP "( |$)${BACKUP_LV}( |$)")
	if [ $count != 1 ]; then
		.log 3 "There are multiple LVs similar to ${BACKUP_LV}."
		exit 1
	fi

	SOURCE_PATH=$(lvs --noheading -o lv_path | grep -P "${BACKUP_LV}( |$)" | tr -d '  ')
	.log 6 "Source Path         | $SOURCE_PATH"

	BACKUP_DIRECTORY="${DESTINATION}/${BACKUP_LV}"
	.log 6 "Destination Path    | $BACKUP_DIRECTORY"

	SNAPSHOT_NAME="${BACKUP_LV}_snapshot"
	.log 6 "Snapshot Name       | $SNAPSHOT_NAME"

	SNAPSHOT_MOUNT="/mnt/${SNAPSHOT_NAME}"
	.log 6 "Snapshot Mountpoint | $SNAPSHOT_MOUNT"

	lvcreate -L${BUFFER_SIZE} -s -n ${SNAPSHOT_NAME} ${SOURCE_PATH}

	SNAPSHOT_PATH=$(lvs --noheading -o lv_path | grep $SNAPSHOT_NAME | tr -d '  ')
	.log 6 "Snapshot Path       | $SNAPSHOT_PATH"

	### Check if Backup Device is mounted. If not, tell user to mount
	### or initizalize Backup Device
	#
	if [ ! -e ${DESTINATION}/00-backup-mounted ] ; then
		.log 3 "Backup Device not mounted/initialized. Run touch 00-backup-mounted."
		exit 1
	fi

	### Create the snapshot mount-point
	#
	if [ ! -d ${SNAPSHOT_MOUNT} ] ; then
	mkdir ${SNAPSHOT_MOUNT}
	fi

	### Protect the snapshot mount-point
	#
	chmod go-rwx ${SNAPSHOT_MOUNT}

	### Mount the snapshot read-only
	#
	mount -o ro ${SNAPSHOT_PATH} ${SNAPSHOT_MOUNT}

	DF=$(df -hlP ${SNAPSHOT_MOUNT} | awk 'int($5)>80{print "Partition "$1" has only "$4" free space left."}')
	
	if [ "$DF" ]
	then
		echo "Time: $(date +%F_%T)" >> $MYDIR/_lv-size-notice.log
		echo $DF | tee -a $MYDIR/_lv-size-notice.log
	fi

	DF=$(df -h | grep ${SNAPSHOT_MOUNT})
	.log 5 ${DF}


	### BTRFS Checks
	#
	### Check, if Destination supports BTRFS
	if (stat -f -c %T ${DESTINATION} | grep -q 'btrfs')
	then
		BTRFS_DEST=true
	else
		BTRFS_DEST=false
	fi
	.log 6 "Dest. BTRFS capable | $BTRFS_DEST" 

	### Check, if Source supports BTRFS
	if (stat -f -c %T ${SNAPSHOT_MOUNT} | grep -q 'btrfs')
	then
		BTRFS_SRC=true
	else
		BTRFS_SRC=false
	fi
	.log 6 "Src. BTRFS capable  | $BTRFS_SRC"

	if [ "$BTRFS_DEST" = true ] && [ "$BTRFS_SOURCE" = true ]
	then
		.log 5 "You should consider backing up this volume using BTRBK!"
	fi

	### Check, if BTRBK is installed
	if ! command -v btrbk >/dev/null
	then
		.log 5 "You will find BTRBK on github: https://github.com/digint/btrbk"
	fi


	if [ ! $NO_RSYNC ]; then
		### Backup the data
		#
		.log 7 "START rsync transfer"
		echo "Time: $(date +%F_%T)" >> ${BACKUP_DIRECTORY}/_backup.log
		# rsync options for more detailed output: --stats --info=progress2
		rsync -a --delete --delete-excluded -h --info=progress2 \
			--exclude-from "$MYDIR/exclude-rsync.txt" \
			${SNAPSHOT_MOUNT}/ ${BACKUP_DIRECTORY}/ | tee -a ${BACKUP_DIRECTORY}/_backup.log
	else
		.log 3 "NO BACKUP WAS CREATED" | tee -a ${BACKUP_DIRECTORY}/_backup.log
	fi

	### Unmount the Snapshot
	#
	umount ${SNAPSHOT_MOUNT}

	### Delete Mountpoint
	#
	rmdir ${SNAPSHOT_MOUNT}

	### Remove the snapshot volume
	#
	lvremove -f ${SNAPSHOT_PATH}
}

while getopts ":acl:d:nv::" opt; do
  case $opt in
    a ) 
	  BACKUP_ALL=1
	  ;;

	c )
	  clean-all
	  exit 0
	  ;;

    l )
      BACKUP_LV=${OPTARG}
      ;;

    d )
      DESTINATION=${OPTARG}
      ;;

    v ) # Verbose Level
	  __VERBOSE=${OPTARG}
      ;;

    n )
      NO_RSYNC=1
      echo "Disable Rsync"
      ;;

    h ) # Display help.
      usage
      exit 0
      ;;

    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  
  esac
done

if [ ! "$DESTINATION" ]
then
    echo "Please specify a destination using the -d option!"
    exit 1
fi

# Measure Execution Time
START_TIME=$SECONDS

if [ "$BACKUP_ALL" ]; then
	clean-all

	for BACKUP_LV in $(lvs --noheading -o lv_name | grep -v -e 'swap' -e 'swp' | tr -d '  ')
	do
		echo
		if grep -Fxq "$BACKUP_LV" $MYDIR/exclude-lv.txt
		then
		    echo "--- $BACKUP_LV will not be backed up. It is listed in exclude-lv.txt --- "
		    echo
		else
		    echo "--- Backup of $BACKUP_LV ---"
		    echo
		    backup 
		fi
	done
else
	if [ ! "$BACKUP_LV" ]
	then
	    echo "Please provide a lv_name using the -l option!"
	    exit 1
	fi

	clean-all
	backup
fi

# Print the Execution Time
ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "$(($ELAPSED_TIME/60)) min $(($ELAPSED_TIME%60)) sec"    
#> 1 min 5 sec
