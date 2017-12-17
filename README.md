# LVM Rsync Backup

These Bash script help us to backup linux LVs via rsync. This script does not keep multiple versions of the backed up lv, as it is meant to be used on destinations which create snapshots on their own, like SynologyNAS running on btrfs filesystem.

If you want to keep multiple versions, take a look at <https://github.com/bamford/lvm-rsync-backup>.

## Backup a single LV
1. Mount your backup device to the desired folder, for example to */mnt/backup*
2. Run script via command or define a cronjob

```bash
lvm-rsync-backup.sh my-lv-disk /mnt/backup
```

```bash
# The path variable needs to be set
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Sent output to
MAILTO="mail@example.com"

# 00:00 Create Snapshot at destination
# 00:05 Backup my-lv-disk
5 0 * * * /etc/backup/lvm-rsync-backup.sh my-lv-disk /mnt/backup 2>&1
```

Don't forget to create a scheduled task that creates the filesystem-snapshots at your backup destination.

## Backup all LVs
To backup all LVs currently active on the machine, use the script **backup-lvs.sh**, which uses **lvs** to get the names of every lv. It will exclude LVs that have *swp* or *swap* in their name, as they cannot be mounted. This script uses **lvm-rsync-backup.sh**, therefore save both of them to */etc/backup*.

1. Mount your backup device to the desired folder, for example to */mnt/backup*
2. Run script via command or define a cronjob

```bash
/etc/backup/backup-lvs.sh /mnt/backup
```

```bash
# The path variable needs to be set
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Sent output to
MAILTO="mail@example.com"

# 00:00 Create Snapshot at destination
# 00:05 Backup my-lv-disk
5 0 * * * /etc/backup/backup-lvs.sh /mnt/backup 2>&1
``` 
