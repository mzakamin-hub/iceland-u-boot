# iceland-u-boot

U-Boot for the OnePlus Pad 4 (`iceland`, SM8850P). The tablet's own boot loader (ABL) starts it from the `boot_b`
partition. This is the same boot path as the OnePlus 15 (infiniti-mainline). The source is a patch queue on the upstream
tag v2026.10-rc5, and every commit keeps its author.

Where it fits: in the [boot chain](https://github.com/mzakamin-hub/iceland-mainline#boot-chain) of the hub, U-Boot is the
boot menu. It offers Fedora, BlissROM on the dual-boot layout, or the boot loader's fastboot. It starts Fedora from the
EFI programs of the disk image, and it never resets or powers off by itself.

## Current release

The [`v7-2026-10-17` release](https://github.com/mzakamin-hub/iceland-u-boot/releases/tag/v7-2026-10-17) is the install
build v7 (patches 0001-0015):

| File | What it is | SHA-256 |
|---|---|---|
| `u-boot-iceland-v7.img` | the plain image, for a RAM test with `fastboot boot`; writes nothing | `58414017ec3e2b496905b078d2bd1db8ca9bea9a171bdaf44797dcf0671eb784` |
| `u-boot-iceland-v7-footered.img` | the same image with an AVB footer, for `boot_b` | `8ef94a08d7eabac35c8bc97173fa818f13c2d1e53ff14375bcf1207c614f68a3` |

Check with `sha256sum -c SHA256SUMS`.

- The footered image is signed with the public AOSP test key and carries the footer values of the reference tablet's
  `boot_b`. It fits only a tablet whose `boot_b` footer has the same values. For any other tablet, make the footer for
  your own `boot_b`: the partition name `boot`, the partition size 100,663,296 bytes, the key that your `vbmeta_b`
  chains `boot` with, and your `boot_b`'s rollback index, OS version and patch level. The install guide names
  `avbtool add_hash_footer` as the standard tool ([INSTALL-GUIDE section 2](https://github.com/mzakamin-hub/iceland-mainline/blob/main/docs/INSTALL-GUIDE.md#2-what-you-need)).
- The boot header values in `uboot.pin` must match the `boot_b` of the tablet you write (anti-rollback).
- A rebuild does not give the same hash, because U-Boot embeds its build time.

The earlier release [v4-2026-10-15](https://github.com/mzakamin-hub/iceland-u-boot/releases/tag/v4-2026-10-15) (patches
0001-0012) has no BlissROM entry.

## What is in the repository

| Path | Content |
|---|---|
| `uboot.pin` | the upstream tag and commit, the infiniti base commit, the expected tree hashes, the mkbootimg pin and the boot header values |
| `patches/0001-infiniti/` | 14 commits from infiniti-mainline/u-boot: Kaanapali clocks, eUSB2, the PMIC arbiter, the ABL memory map, EFI from `userdata`, OnePlus 15 |
| `patches/0002-iceland/` | the Pad 4 board (0001-0003) and the install build (0004-0015): the install environment, no reset by itself, USB without ABL, the boot menu, the BlissROM entry |
| `docs/DUAL-BOOT.md` | the U-Boot side of the dual boot: the menu, the gate, how BlissROM starts, and the build and write of v7 |
| `tools/install/` | the build record and checksums of the earlier install build (v3) |
| `scripts/prepare.sh`, `scripts/build.sh` | the source tree, with its tree hashes checked, and the build |

## Build

Needs an aarch64 cross compiler (`gcc-aarch64-linux-gnu`). The build needs network access: `scripts/build.sh` clones the
pinned `mkbootimg` (commit `808ecd09`).

```bash
git clone https://github.com/mzakamin-hub/iceland-u-boot
cd iceland-u-boot
scripts/prepare.sh ./src        # v2026.10-rc5 + the infiniti patches + the Pad 4 patches; tree hashes checked
scripts/build.sh ./src ./out    # CROSS_COMPILE=aarch64-linux-gnu- by default; JOBS=N to limit parallelism
ls out/dist/
```

A build of your own is not the tested image. Test it from RAM with `fastboot boot` before any write. The install steps
are in the [manual install](https://github.com/mzakamin-hub/iceland-mainline#manual-install) section of the hub.

## Licence

Licence: GPL-2.0+ (U-Boot `Licenses/`).

## Related repositories

- [iceland-mainline](https://github.com/mzakamin-hub/iceland-mainline): the project, the install guide and the dual-boot guide.
- [iceland-linux](https://github.com/mzakamin-hub/iceland-linux): the kernel that U-Boot starts.
- [iceland-firmware](https://github.com/mzakamin-hub/iceland-firmware): the generic firmware files.
