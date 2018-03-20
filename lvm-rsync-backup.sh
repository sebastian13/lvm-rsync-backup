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

	DELETE_PATH=$(lvs --noheading -o lv_path | grep -P "( |$)$DELETE_LV( |$)" | tr -d '  ')
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

	DF=$(df -hlP ${SNAPSHOT_MOUNT} | awk 'int($5)>80{print "Partition "$1" has only "$4" free."}')
	
	if [ "$DF" ]
	then
		echo $DF
	fi

	DF=$(df -h | grep ${SNAPSHOT_MOUNT})
	.log 5 ${DF}

	if [ ! $NO_RSYNC ]; then
		### Backup the data
		#
		.log 7 "START rsync transfer"
		rsync -a --delete --delete-excluded --stats -h \
			--exclude *_snapshots \
			--exclude .@upload_cache \
			--exclude @Recycle \
			--exclude .papierkorb \
			--exclude *TemporaryItems \
			--exclude *DS_Store \
			${SNAPSHOT_MOUNT}/ ${BACKUP_DIRECTORY}/
	else
		.log 3 "NO BACKUP WAS CREATED"
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

if [ "$BACKUP_ALL" ]; then
	clean-all

	for BACKUP_LV in $(lvs --noheading -o lv_name | grep -v -e 'swap' -e 'swp' | tr -d '  ')
	do
		backup
	done
else
	if [ ! "$BACKUP_LV" ]
	then
	    echo "Please provide a lv_name using the -l option!"
	    exit 1
	fi
	clean
	backup
fi
