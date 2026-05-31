# Jellyfin

Less of a "setup" runbook — more "what to know and what can't be done."

## Initial setup

First-run wizard walks through:
- Admin user
- Library paths (point at `/media/movies`, `/media/tv_shows` etc. inside the container)
- Metadata language

Nothing exotic. Defaults are mostly fine.

## Hardware transcoding: NOT POSSIBLE in this stack

The server runs inside a VM with a QEMU virtual VGA controller (PCI `1234:1111`). There's no real GPU passed through. `/dev/dri/card0` exists but no `renderD128` render node, so no VA-API / NVENC / QSV.

Implication: **all transcoding is CPU-only.** A 4K HEVC transcode can max out the CPU and stutter.

### What to do about it

Three options:

1. **Accept it (recommended for homelab).** Pick streaming clients that **direct-play** 4K HEVC HDR — modern smart TVs (LG WebOS, Samsung Tizen, Apple TV 4K, Shield TV, Roku Ultra, Fire TV 4K Max) all do. When direct-play works, the server just streams raw bytes — no transcoding, no CPU load.

2. **GPU passthrough (advanced).** Pass a real GPU from the hypervisor host into this VM. Requires IOMMU + VFIO on the host. Best result, most complex.

3. **Cap software transcoding** in Jellyfin → **Playback → Transcoding**:
   - **Transcoding thread count:** `4` (or half your vCPUs)
   - **Encoding preset:** `veryfast` (massive CPU savings, minor quality drop)
   - **Throttle Transcodes:** ON
   - Leave **Allow encoding in HEVC** and **Allow encoding in AV1** OFF (encoder is much slower than H.264; H.264 output is universal anyway)

## Library breakdown (snapshot from setup)

For context on transcode load:

| Codec | Roughly % | Direct-play friendly? |
|---|---|---|
| H.264 | 47% | Universal |
| HEVC (H.265) | 36% | Modern clients only |
| MPEG-4 (XviD/DivX) | 13% | Older clients prefer this |
| Old AVI, VC-1 | 3% | Often needs transcode |
| VP9 | 1% | Web/Chromecast |
| AV1 | <1% | Newest clients only |

The 36% HEVC is what makes transcoding decisions matter — if a client can't HEVC, the server has to do real work.

## Subtitles

Jellyfin doesn't need subtitle config — Bazarr writes `.srt` / `.ass` files into the media folders alongside the video files, and Jellyfin auto-picks them up on its next library scan.

## Notifications

Set up through plugins (Notifications plugin in the catalog). Not configured in this stack.
