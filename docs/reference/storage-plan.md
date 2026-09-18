# Storage plan: TrueNAS on the Aoostar WTR Pro

Decided 2026-09-16. Three 18 TB refurb HDDs go into a TrueNAS VM on Proxmox.
The docker VM keeps its volumes on NVMe and reaches media over NFS.

Steps 1-3 done 2026-09-18, see "Built so far". Steps 4-7 still open.

## The drives

HPE-branded Seagate Exos X18, model `MB018000GYDKR`, bought refurb from Bargain Hardware.

| Serial | Power-on hours | Reallocated | SMART long test |
|---|---|---|---|
| ZR543CQ0 | 25128 | 0 | passed 2026-09-18 |
| ZR55RJCH | 25120 | 0 | passed 2026-09-18 |
| ZR55R9J3 | 25129 | 0 | passed 2026-09-18 |

About 2.9 years of use each, sequential serials, so almost certainly one batch out of one server.
Batch drives can fail around the same time, which is the argument for the `usb` and rsync.net copies.

**Return window ends about 2026-12-16** (90 days). Run a scrub and re-check SMART in late November,
while a bad drive can still go back.

No `badblocks` write test. The long read test passed on all 54 TB and filling the pool is the write test.

TrueNAS 25.10 removed the S.M.A.R.T. test scheduler from the UI. iX's position is that the built-in
90-minute SMART polling plus ZFS plus the weekly scrub cover it, so no scheduled tests are configured.
Cron is the documented way back if that ever proves wrong.

## Built so far (2026-09-18)

- TrueNAS 25.10.7 Goldeye, fresh install, VM 102 on `pve`, `192.168.1.102` static, hostname `truenas`.
- VM rebuilt: q35 + OVMF, CPU `host`, 16 GB fixed, both SATA controllers passed through, `onboot`.
- Pool `tank` created, RAID-Z1, 3 wide, 32.57 TiB usable. Weekly scrub, Sundays 00:00.
- Five datasets, user `media` (1000) and group `media` (1000), personal user `darthvader`.
- NFS exports limited to `192.168.1.100` and `192.168.1.108`.

### Deviations from the plan below

- **No ZFS encryption anywhere.** Chosen deliberately, encrypt in the backup tool instead
  (restic or `rclone crypt`) when rsync.net goes in. Changing this means recreating the dataset
  and `zfs send | recv` the data across.
- **Multiprotocol preset, not POSIX**, on `media`, `downloads`, `backups`, so SMB and NFS share them.
  `share` stayed SMB-only.
- **KIOXIA SSD still installed**, so bay 4 is not free for a 4th 18 TB yet. It held an old L2ARC
  device, no data. It is a consumer drive with no power-loss protection, so it is a poor SLOG
  candidate. Unassigned for now.
- **setgid on `media`, `downloads`, `backups`** so files written over SMB keep group `media`.
- **`builtin_users` removed** from the `share` ACL, otherwise every local account, `media` included,
  could modify personal files.
- **`maproot_user`/`maproot_group` = `media`** on the `backups` export, so Stackr's root-owned writes
  land correctly instead of being squashed to nobody.

- **RustFS installed as a TrueNAS app** (app version 1.0.0-beta.12, chart 1.1.30), running as uid/gid 568
  (`apps`), data on host path `/mnt/tank/s3`, not an ixVolume, so the existing snapshot and replication
  tasks cover it. API on port 30292, console on 30293. `tank/s3` is owned `apps:apps`, mode 750.
  Not yet exposed through Traefik, no buckets or users created yet.
  Note: no wildcard cert exists (Traefik uses the TLS-ALPN challenge), so bucket-per-subdomain
  addressing is not possible; path-style URLs only. Authelia forward-auth cannot protect the S3 API,
  only the console.

### Still to do

- Email alerts (needs a mail credential).
- RustFS: buckets, per-app users and policies, Traefik exposure.
- DHCP reservations for `.100` and `.108`, or the NFS exports break when an address changes.
- `tank/s3` still `root:root`, set its owner when RustFS is deployed.

## Hardware facts (checked on the host)

- Proxmox boots from the 256 GB Patriot NVMe. Two 1 TB Crucial NVMe form the VM mirror.
- Two SATA controllers, `07:00.0` and `07:00.1`, each alone in its IOMMU group (25, 26).
- Each controller exposes one port that fans out to two bays via a port multiplier.
  Two bays share one 6 Gbit link. Fine for HDDs.
- Today: KIOXIA 894 GB SSD in one bay, WD 3 TB in another. Both get pulled.
  (WD pulled. KIOXIA still in, see deviations.)
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

Retention below is what is actually configured (longer than first planned).

| Dataset | ACL mode | Snapshots | To `usb` | To rsync.net |
|---|---|---|---|---|
| `tank/share` | SMB | hourly, keep 90 days | yes | yes |
| `tank/backups` | Multiprotocol | daily 00:00, keep 60 days | yes | yes |
| `tank/s3` | POSIX | daily 00:00, keep 60 days | yes | yes |
| `tank/media` | Multiprotocol | weekly Sun 00:00, keep 12 weeks | as much as fits | no |
| `tank/downloads` | Multiprotocol | none | no | no |

Deleted files only free space once every snapshot holding them expires, so a large delete on
`tank/media` stays on disk for up to 12 weeks.

Existing `MEDIA_STORAGE_*` subfolders (Anime, tv_shows, Movies, ...) stay plain folders under `tank/media`.
~~Enable ZFS encryption on `share`, `backups`, `s3` so rsync.net holds them encrypted.~~
Dropped, see deviations. Encryption happens in the backup tool instead.

## Permissions

- TrueNAS user `media` uid 1000, group `media` gid 1000. Matches `PUID`/`PGID` in `.env`.
- Personal SMB user joins group `media`.
- `tank/media`, `tank/downloads`, `tank/backups`: owner `media:media`, mode 775, plus setgid.
- `tank/share`: SMB ACL mode, its own dataset so modes never collide with NFS.
  Owner `darthvader:darthvader`, `builtin_users` entry removed.

NFS has no authentication: the client simply claims a uid and the server believes it.
So NFS is for container traffic behind an IP allow-list, and anything personal goes over SMB
with a password. That is why `share` is not exported over NFS.

## Docker VM side

- Mount NFS in the VM via fstab with `x-systemd.automount`, not docker NFS volumes.
  One mount, plain bind paths in compose, hardlinks keep working.
- Only `.stackr.yaml` changes: `paths.pools.HDD`, `paths.backup_dir`, `paths.custom.MEDIA_*` point at the NFS mount.
  No stack changes.

## Migration order

1. ~~Drives arrive. Pull KIOXIA and WD, install the three 18 TB.~~ done (KIOXIA still in)
2. ~~Create the TrueNAS VM, pass both SATA controllers, install.~~ done
3. ~~Create `tank` RAID-Z1, the five datasets, user and group `media`.~~ done
4. Copy the USB drive contents to `tank/media` and `tank/backups` over the network.
   Verify sizes and file counts match before touching the USB drive. This is the irreversible step.
5. NFS exports, mount in the docker VM, update `.stackr.yaml`, restart the media stack, test.
6. Move the USB drive to TrueNAS, wipe it, create pool `usb`, set up replication tasks.
7. rsync.net replication, RustFS app, SMB share.

## Risks

- Refurb drives + RAID-Z1 + port multiplier. A flaky multiplier can drop two drives at once.
  The `usb` and rsync.net copies are not optional.
- Storage is down whenever the TrueNAS VM is down. Docker VM must tolerate a missing mount at boot.
