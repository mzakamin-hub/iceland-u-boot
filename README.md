# iceland-u-boot

U-Boot for the OnePlus Pad 4 (`iceland`, SM8850P), chainloaded by the stock OnePlus ABL — the same boot path
as the OnePlus 15 (infiniti-mainline). Kept as a patch queue on an upstream tag; every commit keeps its author.

| Path | Content |
|---|---|
| `uboot.pin` | upstream tag, infiniti commit, expected tree hashes, mkbootimg pin, boot header values |
| `patches/0001-infiniti/` | infiniti-mainline/u-boot `main` (14 commits: Kaanapali clocks, eUSB2, PMIC arb v8, ABL memory map pass-through, EFI from userdata, OnePlus 15) |
| `patches/0002-iceland/` | OnePlus Pad 4 board (DTS, `iceland_defconfig`, `iceland.env`; 0001-0003) + the install build (0004-0010, see below) |
| `tools/install/` | build / check tooling and RAM-boot probes of the install build |
| `scripts/prepare.sh` / `scripts/build.sh` | source tree with verified hashes / U-Boot + boot images |

```
scripts/prepare.sh ./src && scripts/build.sh ./src ./out
```

Boot flow: ABL → `boot_a` = U-Boot → `bootefi bootmgr` on the disk image in `userdata` (ESP → systemd-boot/GRUB
→ Linux with `dtb/qcom/kaanapali-oneplus-iceland.dtb`) → falls back to `fastboot usb 0`.

## First test (RAM only — nothing is written)
With the tablet in fastboot mode (Power + Volume Down), the user runs:
```
fastboot boot u-boot-iceland-v4.img      # if ABL refuses: fastboot boot u-boot-iceland-v2.img
```
Expected: U-Boot text on the panel (ABL framebuffer), then — with no disk image in userdata yet — U-Boot's own
fastboot (`fastboot devices` lists it). Report what the screen shows. Reboot (hold Power) returns to stock.

Open questions this test answers: RAM boot allowed by OnePlus ABL? header v4 vs v2? framebuffer geometry
(3392x2400, stride 13568)? UFS/GPT visible (`part list scsi 0`)?

Licence: GPL-2.0+ (U-Boot `Licenses/`). Boot image header values must match stock (`uboot.pin`).

## Install build: patches 0004-0010 (proven on the tablet, 10 Oct 2026)

`patches/0002-iceland/` now carries the install build on top of the board (0001-0003). `scripts/prepare.sh`
applies all of it and checks `TREE_AFTER_0002_iceland` (= the tree that was built and tested as "v3",
U-Boot commit aac9e744ec6f, tree 158b0f7851ad). `scripts/build.sh` then makes the install build
(`iceland_defconfig`, `iceland.env`).

| Patch | What it does |
|---|---|
| 0004 cmd: blkmap | `blkmap create <label> <blksz>` (4096-byte blocks for a RAM-mapped UFS image) and `map ... mem <addr> reserve` (LMB reservation, so EFI programs never get pages inside the disk) |
| 0005 efi_loader: disk | `EFI_DISK_WRITE_BLKMAP_ONLY`: every block device except blkmap disks is read-only for EFI programs |
| 0006 board: iceland: install environment | boots the Fedora disk image in userdata through the EFI boot manager; fastboot fallback that starts a RAM kit (Android boot image) or a rehearsal head (gzip image mapped with 4096-byte blocks); `bootdelay=-2`; the three UFS lines marked `ICELAND_INSTALL_ONLY` and `iceland-rehearsal.env` without them (the rehearsal build has no SCSI / UFS code) |
| 0007 cmd: fastboot | `${fastboot_idle_timeout}`: `fastboot usb` ends after that many idle seconds |
| 0008 board: iceland: never reset or power off | fastboot loop that HOLDs 60 s and starts fastboot again forever (no poweroff / reset in any env line), `CONFIG_PANIC_HANG`, one `scsi scan` per boot, `fedora_bootopt` only with a partition 1. Cause: on C0 #1 the install build started from boot_b reset itself about 7 times and ABL counted slot b down to unbootable |
| 0009 board: iceland: USB without ABL | U-Boot powers USB itself, as Linux does: TCSR USB2 clkref, PHY supplies L4F 0.88 V / L1D 1.2 V over RPMh (RSC v3+ layout, PMH0101 / PMH0110 LDOs), the PMIH0108 eUSB2 repeater on the second SPMI bus (supplies L15B / L5B, stock tuning), USB30 master 200 MHz. Cause: on C0 #2 fastboot failed with "Reset Timed Out / failed to initialize core" because ABL starts USB only in its own fastboot mode |
| 0010 board: iceland: reboot-bootloader | `fastboot reboot-bootloader` writes the reboot reason 2 (bootloader) into PMK8850 SDAM 2 byte 0x48 bits 1-7 (the cell Linux's nvmem-reboot-mode and stock use), reads it back, and resets only after the OKAY: ABL then stays in its fastboot and boots no slot. U-Boot still never resets by itself |

Tablet proof (10 Oct 2026; the RAM boots wrote nothing, every boot_b write was undone the same day with the
original boot_b image, LineageOS came back on slot b each time):

- RAM T-b v2 (install build with 0009): PASS - fastboot after 2 s, userdata mapped, "no partition 1" in one
  line, boot manager fails cleanly, no reset; slot flags unchanged.
- RAM T-a v2 (usbcold diagnostic: USB put into the cold state of a normal boot first): PASS - fastboot from the
  cold state after 4 s, no "GDSC stuck" / "Reset Timed Out".
- RAM T-d (v3, 0010): PASS - `fastboot reboot-bootloader` -> ABL fastboot after 15 s, flags before = after.
- C0 #2 (0008 in boot_b): U-Boot holds, no reset loop (USB still failing: the reason for 0009).
- C0 #3 (0009 in boot_b, normal boot): U-Boot fastboot enumerated on the PC after 7 s.
- C0 #4 (v3 = 0008-0010 in boot_b): fastboot after 7 s, console clean; `fastboot reboot-bootloader` -> ABL
  fastboot after 14 s with no key press; slot b retry count lowered only by the one U-Boot boot.

Images of the tested v3 build (sha256 only; images are never stored here; the install image gets a per-day AVB
hash footer made from that day's boot_b, so its footered hash is not listed):

| Image | sha256 |
|---|---|
| install `u-boot-iceland-usb.img` (540672 bytes) | 979b40767afba37367354cfe047994acff10b21831f7664933ee30c7dc89f94c |
| rehearsal `u-boot-iceland-rehearsal-usb.img` (no SCSI / UFS) | 8a1b011cea5d16a82ca96eb3964b222300f8509f6bbd7962f073f6d938c3c096 |
| usbcold `u-boot-iceland-usbcold.img` (DIAGNOSTIC, RAM boot only) | 778e979cbdbb51293b5b6a316e79acd1c7e564563a7eb4fe3f9c7a32a53e6dc8 |

A rebuild with `scripts/build.sh` gives the same source tree but not the same image hash (U-Boot embeds its
build time).

`tools/install/` - the PC workflow's build and check tooling (written for the project's WSL layout,
`~/mainline/build/wf/...`; kept as the record of how v3 was built and checked: 189 checks, 0 failures,
`check-v3.txt`): `mk-uboot-v3.sh` (the three variants from one tree + all checks), `check-usb-src.py` (0009
against the Linux DT and drivers), `check-reboot-src.py` (0010), `check-usbcold-env.py` (allow list of the
diagnostic's register writes), `check-header.py` (boot header vs the day's boot_b), `sandbox-check-loop.sh` /
`sandbox-check-usbcold.sh` (the env scripts in a U-Boot sandbox), `spmi-unit/` and `rb-unit/` (host unit tests of
spmi-msm.c against a two-bus v8 arbiter model and of 0010 against a PMK8850 model), `usbcold-extra.env`, and the
RAM-boot probes `uboot-ram-probe.ps1`, `usbcold-ram-probe.ps1`, `rb-ram-probe.ps1` with `check-probe.py` /
`check-probe-rb.py` (their fastboot / adb whitelists: boot, getvar, devices, `oem console`, reboot,
reboot-bootloader only).

Still open: marking slot b successful from Fedora (`qbootctl -m`; U-Boot writes no GPT) and the install-flow
rehearsal with this U-Boot. Writes to the tablet are always run by the owner.
