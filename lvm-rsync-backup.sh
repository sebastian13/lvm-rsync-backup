#!/bin/bash

# Thanks to
# https://github.com/bamford/lvm-rsync-backup

# This script performs a backup of the specified
# system logical volume to a backup logical volume
# located on a separate physical volume.
# It uses an LVM snapshot to ensure the data
# remains consistent during the backup.

# Run via Cron like that
# /etc/backup/lvm-rsync-backup.sh lv_home /mnt/backup &> /var/log/backup-daily-home.log
# or use backup-all-lvm.sh

# Specify the LV to backup
# expected format: samba01
BACKUP_LV=$1
echo "***"
echo "*** START backup of $BACKUP_LV"
echo "***"

# Specify the Backup Mount
# expected format: /mnt/backup-nas01
BACKUP_SERVER=$2

# Remove Tailing Slash, if there is one.
length=${#BACKUP_SERVER}
last_char=${BACKUP_SERVER:length-1:1}
[[ $last_char == "/" ]] && BACKUP_SERVER=${BACKUP_SERVER:0:length-1}; 
echo "BACKUP_SERVER: $BACKUP_SERVER"

BUFFER_SIZE=5G

count=$(lvs | grep -c "\s${BACKUP_LV}\s")
if [ $count != 1 ]; then
	echo "There are multiple LVs similar to ${BACKUP_LV}."
	exit 1
fi
SOURCE_PATH=$(lvs --noheading -o lv_path | grep $BACKUP_LV | tr -d '  ')
echo "SOURCE_PATH: $SOURCE_PATH"

BACKUP_DIRECTORY="${BACKUP_SERVER}/${BACKUP_LV}"
echo "BACKUP_DIRECTORY: $BACKUP_DIRECTORY"

SNAPSHOT_NAME="${BACKUP_LV}_snapshot"
echo "SNAPSHOT_NAME: $SNAPSHOT_NAME"

SNAPSHOT_MOUNT="/mnt/${SNAPSHOT_NAME}"
echo "SNAPSHOT_MOUNT: $SNAPSHOT_MOUNT"

### First check everything was left cleanly last time, and fix if not
#
# If the snapshot mountpoint still exists try unmounting and removing it
#
if [ -d ${SNAPSHOT_MOUNT} ] ; then
umount ${SNAPSHOT_MOUNT}
rmdir ${SNAPSHOT_MOUNT}
fi
#
# If the snapshot logical volume still exists, remove it
#
lvdisplay | grep "LV Name" | grep -q ${SNAPSHOT_NAME}
if [ $? = 0 ]; then
lvremove -f ${SNAPSHOT_NAME}
fi

### Create a logical volume to snapshot the system volume
#
# This is created every time. The volume is deleted at the end of the
# backup as it is not necessary to keep it, wastes space and
# cpu and will freeze when full.
#
# The size of this volume needs to be large enough to contain
# any changes which may happen on the original volume during
# the course of the backup.  For example, with a size of 592M,
# if a 1G file is written the snapshot volume may be frozen!
# To avoid this make size big enough to cope, execute only in
# quiet times (early hours) and make sure this script completes
# gracefully if a frozen snapshot is encountered.
#
lvcreate -L${BUFFER_SIZE} -s -n ${SNAPSHOT_NAME} ${SOURCE_PATH}

SNAPSHOT_PATH=$(lvs --noheading -o lv_path | grep $SNAPSHOT_NAME | tr -d '  ')
echo "SNAPSHOT_PATH: $SNAPSHOT_PATH"

### Create the backup logical volume
#
# This will only usually be necessary on the first run of this
# script, unless for some reason the backup itself has been lost!
#
# The size of the backup volume must be large enough to contain
# the contents of the original volume and any changes which have
# occurred over the length of time for which backups are kept.
# It may therefore be necessary to extend the backup volume manually.
#

### Check if Backup Device is mounted. If not, tell user to mount
### or initizalize Backup Device
#
if [ ! -e ${BACKUP_SERVER}/00-backup-mounted ] ; then
	echo "Backup Device not mounted/initialized. Run touch 00-backup-mounted."
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

if [ $? = 0 ]; then

	### Backup the data
	#
	echo "START rsync transfer"
	rsync -a --delete --delete-excluded --stats \
		--exclude *_snapshots \
		--exclude .@upload_cache \
		--exclude @Recycle \
		--exclude .papierkorb \
		--exclude *TemporaryItems \
		--exclude *DS_Store \
		${SNAPSHOT_MOUNT}/ ${BACKUP_DIRECTORY}/

	### Unmount the Snapshot
	#
	umount ${SNAPSHOT_MOUNT}

else

	echo "Error Mounting the disk"
	echo "*** NO BACKUP WAS CREATED ***"

fi

### Delete Mountpoint
#
rmdir ${SNAPSHOT_MOUNT}

### Remove the snapshot volume
#
lvremove -f ${SNAPSHOT_PATH}
