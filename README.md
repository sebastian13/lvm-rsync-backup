# LVM Rsync Backup

This Bash script helps us backup linux LVs via rsync. It does not keep multiple versions of the backed up lv, as it is meant to be used on destinations which create snapshots on their own, like SynologyNAS running on btrfs filesystem.

If you want to keep multiple versions, take a look at <https://github.com/bamford/lvm-rsync-backup>.

1. Mount your backup device to the desired folder, for example to */mnt/backup*
2. Run script via command or define a cronjob
3. Run some cronjob at your destination, to keep multiple snapshots

## Parameters

Parameter               | Description                                                       | Necessary
:---------------------- | :---------------------------------------------------------------- | ---------       
-a                      | Creates a backup of all mountable Logical Volumes on the system * | if -l not used
-l [lv_name]            | Creates a backup of provided Logical Volume                       | if -a not used
-d [/path/to/directory] | Location, where backups will be created                           | optional
-c                      | Deletes Mountpoints and LVs called *_snapshot                     | optional
-v [1-7]                | Defines the Log Level                                             | optional

\* This will exclude LVs that have *swp* or *swap* in their name, as they cannot be mounted.

## Exclude from Backup

* To exclude **Logical Volumes** from -a Backup create a **exclude-lv.txt** beside lvm-rsync-backup.sh
* To exclude files from **rsync** transfers create a **exclude-rsync.txt** beside lvm-rsync-backup.sh

## Examples

### Backup a single LV

```bash
./lvm-rsync-backup.sh -l lv_home -v7 -d /mnt/backup-nas01
```

### Backup all LVs
```bash
./lvm-rsync-backup.sh -a -v7 -d /mnt/backup-nas01
```

### Crontab
```bash
# The path variable needs to be set
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Sent output to
MAILTO="mail@example.com"

# 00:00 Create Snapshot at destination
# 00:05 Backup my-lv-disk
5 0 * * * /etc/backup/lvm-rsync-backup.sh -l lv_home -v7 -d /mnt/backup-nas01 2>&1
```