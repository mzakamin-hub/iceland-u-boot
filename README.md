# iceland-u-boot

U-Boot for the OnePlus Pad 4 (`iceland`, SM8850P), chainloaded by the stock OnePlus ABL: the same boot path as the
OnePlus 15 (infiniti-mainline). Kept as a patch queue on an upstream tag; every commit keeps its author.

Current state (15 Oct 2026): the U-Boot install build **v4** (0001-0012) is the boot path of the Fedora 44 install: it
sits in `boot_b` and starts Fedora from the disk image in `userdata`. v4 adds a power-on boot menu on the keys to the
install build v3. See [Installing](#installing).

| Path | Content |
|---|---|
| `uboot.pin` | upstream tag, infiniti commit, expected tree hashes, mkbootimg pin, boot header values |
| `patches/0001-infiniti/` | 14 commits from infiniti-mainline/u-boot `main`: Kaanapali clocks, eUSB2, PMIC arbiter v8, ABL memory map pass-through, EFI from userdata, OnePlus 15 |
| `patches/0002-iceland/` | the OnePlus Pad 4 board (0001-0003, DTS, `iceland_defconfig`, `iceland.env`) and the install build (0004-0012, below) |
| `tools/install/` | `BUILD_INFO-v3.txt` and `SHA256SUMS-v3.txt`: the record of the install build v3 |
| `scripts/prepare.sh`, `scripts/build.sh` | source tree with verified hashes; U-Boot and the boot images |

```
scripts/prepare.sh ./src && scripts/build.sh ./src ./out
```

Licence: GPL-2.0+ (U-Boot `Licenses/`). The boot image header values must match stock (`uboot.pin`).

## Boot flow (as installed)

1. ABL (stock, closed) starts the `boot_b` image, checks its AVB footer and counts the tries of slot b.
2. `boot_b` holds the install build v4 with an AVB footer made for the tablet's own `boot_b` (so the footered image's
   hash differs from tablet to tablet; the unfootered build is `23ff0be6`). It shows a boot menu for 5 s (Fedora by default, or the boot loader's
   fastboot; Volume Down moves, Power selects). U-Boot looks for a `fedora` partition (there is none), then runs
   `bootefi bootmgr` on the disk image in `userdata`. If that finds nothing, it falls back to fastboot.
3. The disk image in `userdata` is Fedora's: its EFI programs are shim and GRUB (aarch64). GRUB loads
   `kernel-iceland` (BLS entry) with `dtb/qcom/kaanapali-oneplus-iceland.dtb` and the initramfs. The DTB is
   handed over after U-Boot's fixups (see [iceland-linux packaging](https://github.com/mzakamin-hub/iceland-linux/blob/main/packaging/fedora/README.md)).
4. The install build never resets or powers off by itself (patch 0008). It brings USB up without ABL's help (0009).
   `fastboot reboot-bootloader` returns to ABL's fastboot (0010).

Slot marking. ABL keeps three values per slot: a successful flag, an unbootable flag and a retry count. Each normal
power-on of a slot that is not marked successful uses one try, and flashing `boot_b` resets slot b. U-Boot does not
mark slots; on the installed system `iceland-slot-mark` (iceland-device 0.28-8 and newer) runs Fedora's `qbootctl -m`
once after a good boot. For the same reason the install build never resets by itself: a reset is another boot of the
slot.

## Install build: patches 0004-0012

`patches/0002-iceland/` carries the install build on top of the board (0001-0003). `scripts/prepare.sh` applies all
of it and checks `TREE_AFTER_0002_iceland` in `uboot.pin` (recorded for the install build v4, 0001-0012: U-Boot commit
`e0300255e054`, tree `35655ad58d6a`; v3, 0001-0010, was tree `158b0f7851ad`). `scripts/build.sh` then makes the install build (`iceland_defconfig`,
`iceland.env`).

| Patch | What it does |
|---|---|
| 0004 cmd: blkmap | `blkmap create <label> <blksz>` (4096-byte blocks for a RAM-mapped UFS image) and `map ... mem <addr> reserve` (reserves the memory, so EFI programs never get pages inside the disk) |
| 0005 efi_loader: disk | `EFI_DISK_WRITE_BLKMAP_ONLY`: every block device except blkmap disks is read-only for EFI programs |
| 0006 board: iceland: install environment | boots the Fedora disk image in `userdata` through the EFI boot manager; a fastboot fallback that starts a RAM kit or a rehearsal head; `bootdelay=-2`; the UFS lines are marked `ICELAND_INSTALL_ONLY`, and `iceland-rehearsal.env` leaves them out (the rehearsal build has no SCSI or UFS code) |
| 0007 cmd: fastboot | `${fastboot_idle_timeout}`: `fastboot usb` ends after that many idle seconds |
| 0008 board: iceland: never reset or power off | a fastboot loop that holds for 60 s and starts fastboot again; no poweroff or reset in any environment line; `CONFIG_PANIC_HANG`; one `scsi scan` per boot. Cause: in the first test from `boot_b`, the install build reset itself about seven times and ABL counted slot b down to unbootable |
| 0009 board: iceland: USB without ABL | U-Boot powers USB itself, as Linux does: the TCSR USB2 clock reference, the PHY supplies over RPMh, the eUSB2 repeater on the second SPMI bus, USB30 master at 200 MHz. Cause: ABL starts USB only in its own fastboot mode, and without this fastboot failed with "Reset Timed Out" |
| 0010 board: iceland: reboot-bootloader | `fastboot reboot-bootloader` writes the bootloader reboot reason to the PMIC's SDAM register, reads it back and resets only after OKAY: ABL then stays in its fastboot and boots no slot |
| 0011 board: iceland: ABL's boot mode | reads ABL's boot mode read-only (bootconfig `androidboot.mode`, bootargs `oplusboot.mode`), prints it (`ABL boot mode: normal`) and adds it to the device tree U-Boot hands on; no storage access, never fails the boot |
| 0012 board: iceland: power-on boot menu | a boot menu on the keys in the install environment: it waits until no key is held, shows 5 s with Fedora as the default and an entry for the boot loader's fastboot (the reboot reason is stored in the PMIC and read back before the reset); Volume Down + Power at power-on still reaches ABL's fastboot |

Tested on the tablet (RAM boots write nothing; every test write of `boot_b` was undone with the saved original):

- RAM boot of 0009: fastboot after 2 s, `userdata` mapped, the boot manager fails cleanly, no reset, slot flags
  unchanged.
- RAM boot of a USB cold-state diagnostic: fastboot from the cold state after 4 s, no "GDSC stuck" and no
  "Reset Timed Out".
- RAM boot of v3 (0010): `fastboot reboot-bootloader` gives ABL's fastboot after 15 s, slot flags unchanged.
- `boot_b` with v3 (0008-0010): fastboot after 7 s; `fastboot reboot-bootloader` gives ABL's fastboot after 14 s with
  no key press. One normal boot into U-Boot used one try of slot b; `reboot-bootloader` used none.
- v4: the menu (Fedora, Boot loader) appears at power-on and Fedora boots after the timeout; Volume Down moves the
  highlight, and Power on "Boot loader (fastboot)" lands in ABL's fastboot with the slot flags unchanged.

Build images of v4 (sha256; the images are not published):

| Image | sha256 |
|---|---|
| install `u-boot-iceland-usb.img` | `23ff0be6b688560de8a63c5c49cf99b10a0a023fd36f4d9542edcf2660ef2c84` |
| rehearsal `u-boot-iceland-rehearsal-usb.img` (no SCSI or UFS) | `a9fe780aafe3e6d190120b1ddf5fb9a698fcbec9825f94e16786bb3df62e8804` |

Build images of v3 (sha256; the images are not published, see below):

| Image | sha256 |
|---|---|
| install `u-boot-iceland-usb.img` (540,672 bytes) | `979b40767afba37367354cfe047994acff10b21831f7664933ee30c7dc89f94c` |
| rehearsal `u-boot-iceland-rehearsal-usb.img` (no SCSI or UFS) | `8a1b011cea5d16a82ca96eb3964b222300f8509f6bbd7962f073f6d938c3c096` |
| usbcold `u-boot-iceland-usbcold.img` (diagnostic, RAM boot only) | `778e979cbdbb51293b5b6a316e79acd1c7e564563a7eb4fe3f9c7a32a53e6dc8` |

The image written to `boot_b` carries an AVB footer made for the tablet's current `boot_b`, so its hash differs from the
plain build's. A rebuild with `scripts/build.sh` gives the same source tree but
not the same image hash, because U-Boot embeds its build time.

Boot header values (`uboot.pin`, `tools/install/BUILD_INFO-v3.txt`): header v4, `os_version` 17.0.0, patch level
2026-09, mkbootimg `808ecd09`. A `boot_b` image must carry the boot header values of the tablet's current `boot_b` (anti-rollback).

## Installing

The install writes two partitions: the Fedora disk image into `userdata`, and this install build, with an AVB footer
made for the tablet's current `boot_b`, into `boot_b`. The requirements, the steps and the way back are in
[iceland-mainline/docs/INSTALL-GUIDE.md](https://github.com/mzakamin-hub/iceland-mainline/blob/main/docs/INSTALL-GUIDE.md).
A later U-Boot update is the same `boot_b` write with a newly footered build.
