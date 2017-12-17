#!/bin/bash

# List all LVs via lvs and run the lvm-rsync-backup script
# with each lv. Specify your destination similar to this:
# ./backup-lvs.sh /mnt/backup
#

# lvs --noheading -o lv_name
# List the lv_name of all LVs

# grep -v -e 'swap' -e 'swp'
# Exclude swap and swp lvs

for lv in $(lvs --noheading -o lv_name | grep -v -e 'swap' -e 'swp' | tr -d '  ')
do
	/etc/backup/lvm-rsync-backup.sh $lv $1
done
