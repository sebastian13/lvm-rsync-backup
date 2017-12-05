#!/bin/bash

# List all LVs via lvs and run the lvm-rsync-backup script
# with each lv. Specify your destination similar to this:
# ./backup-lvs.sh /mnt/backup
#

for lv in $(lvs --noheading -o lv_name | tr -d '  ')
do
	/etc/backup/lvm-rsync-backup.sh $lv $1
done