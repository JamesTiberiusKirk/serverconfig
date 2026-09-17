# Storage plan: TrueNAS on the Aoostar WTR Pro

Decided 2026-09-16. Three 18 TB refurb HDDs go into a TrueNAS VM on Proxmox.
The docker VM keeps its volumes on NVMe and reaches media over NFS.

## Hardware facts (checked on the host)

- Proxmox boots from the 256 GB Patriot NVMe. Two 1 TB Crucial NVMe form the VM mirror.
- Two SATA controllers, `07:00.0` and `07:00.1`, each alone in its IOMMU group (25, 26).
- Each controller exposes one port that fans out to two bays via a port multiplier.
  Two bays share one 6 Gbit link. Fine for HDDs.
- Today: KIOXIA 894 GB SSD in one bay, WD 3 TB in another. Both get pulled.
- 64 GB RAM on the host.

## Layout

| Thing | Lives on | Docker VM sees it as |
|---|---|---|
| Docker volumes, databases | NVMe mirror (existing SSD pool) | virtual disk, as today |
| Media, realdebrid downloads | `tank/media`, `tank/downloads` | NFS mount |
| Stackr volume backups | `tank/backups` | NFS mount, `backup_dir` |
| Personal files | `tank/share` | not mounted, SMB clients hit TrueNAS |
| S3 | `tank/s3` | RustFS app on TrueNAS, HTTP |
| USB 16 TB | own pool `usb` on TrueNAS | not mounted, replication target |

Bay 4 stays empty for a 4th 18 TB later. RAID-Z1 vdev expansion needs OpenZFS 2.3 (TrueNAS 25+).
No L2ARC or SLOG. Media is read once, sync writes live on NVMe. Add a single SATA SSD as L2ARC only if a benchmark says so.

## TrueNAS VM

- 16 GB RAM, fixed, no ballooning. 4 cores, CPU type `host`.
- 32 GB boot disk on the NVMe mirror. OS only.
- PCI passthrough of both SATA controllers. Never give TrueNAS a virtual disk for data. ZFS on a zvol corrupts pools.
- Same bridge as the docker VM. NFS traffic never leaves the box.
- Proxmox startup order: TrueNAS first, docker VM with a 60 s delay.

## Pool and datasets

Pool `tank`, RAID-Z1, 3x 18 TB, about 36 TB usable.

| Dataset | ACL mode | Snapshots | To `usb` | To rsync.net |
|---|---|---|---|---|
| `tank/share` | SMB | hourly, keep 30 days | yes | yes |
| `tank/backups` | POSIX | daily, keep 14 | yes | yes |
| `tank/s3` | POSIX | daily, keep 14 | yes | yes |
| `tank/media` | POSIX | weekly, keep 4 | as much as fits | no |
| `tank/downloads` | POSIX | none | no | no |

Existing `MEDIA_STORAGE_*` subfolders (Anime, tv_shows, Movies, ...) stay plain folders under `tank/media`.
Enable ZFS encryption on `share`, `backups`, `s3` so rsync.net holds them encrypted.

## Permissions

- TrueNAS user `media` uid 1000, group `media` gid 1000. Matches `PUID`/`PGID` in `.env`.
- Personal SMB user joins group `media`.
- `tank/media`, `tank/downloads`, `tank/backups`: owner `media:media`, mode 775, POSIX ACL, inherit.
- `tank/share`: SMB ACL mode, its own dataset so modes never collide with NFS.

## Docker VM side

- Mount NFS in the VM via fstab with `x-systemd.automount`, not docker NFS volumes.
  One mount, plain bind paths in compose, hardlinks keep working.
- Only `.stackr.yaml` changes: `paths.pools.HDD`, `paths.backup_dir`, `paths.custom.MEDIA_*` point at the NFS mount.
  No stack changes.

## Migration order

1. Drives arrive. Pull KIOXIA and WD, install the three 18 TB.
2. Create the TrueNAS VM, pass both SATA controllers, install.
3. Create `tank` RAID-Z1, the five datasets, user and group `media`.
4. Copy the USB drive contents to `tank/media` and `tank/backups` over the network.
   Verify sizes and file counts match before touching the USB drive. This is the irreversible step.
5. NFS exports, mount in the docker VM, update `.stackr.yaml`, restart the media stack, test.
6. Move the USB drive to TrueNAS, wipe it, create pool `usb`, set up replication tasks.
7. rsync.net replication, RustFS app, SMB share.

## Risks

- Refurb drives + RAID-Z1 + port multiplier. A flaky multiplier can drop two drives at once.
  The `usb` and rsync.net copies are not optional.
- Storage is down whenever the TrueNAS VM is down. Docker VM must tolerate a missing mount at boot.
