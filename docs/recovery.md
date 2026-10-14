# Snapshot and offline recovery

The R1 reference root is ext4 on NVMe. It does not claim atomic Btrfs-style
snapshots. `omarchy-jetson-snapshot` instead creates full file-level trees under
`/var/lib/omarchy-jetson/snapshots`; unchanged files in later snapshots are
hard-linked to the previous tree. Virtual filesystems, temporary mounts and the
snapshot store itself are excluded. Every regular file is checksummed.

Create snapshots while the system is quiet. Stop mutable application workloads
before an upgrade, then run:

```sh
sudo omarchy-jetson-snapshot create before-upgrade
sudo omarchy-jetson-snapshot list
```

A live file-level snapshot is suitable for package/configuration rollback, but
is not a transactionally consistent database backup. Applications retain their
own backup procedures.

## Restore from recovery media

Never restore over the running `/` filesystem. Boot trusted recovery media,
identify the NVMe partition by model, size and UUID, and mount that verified
partition at `/mnt/target`. Do not select an `mmcblk` device.

After inspecting the mount, create the one-use operator marker and restore:

```sh
sudo touch /mnt/target/.omarchy-jetson-restore-target
sudo env OMARCHY_SNAPSHOT_ROOT=/mnt/target/var/lib/omarchy-jetson/snapshots \
  omarchy-jetson-snapshot restore before-upgrade /mnt/target --confirmed
```

The tool refuses `/` as a target, refuses an unmarked directory, verifies the
snapshot checksums before copying, stays on one filesystem, and removes files
from the target that are absent from the selected snapshot. Review the snapshot
name and mount twice before adding `--confirmed`.
