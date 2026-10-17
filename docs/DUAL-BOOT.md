# Dual boot BlissROM + Fedora: the U-Boot side

The install build **v7** (patches 0001-0015) in `boot_b` turns the power-on menu into a dual boot:
**Fedora / BlissROM / Boot loader (fastboot)**. This page covers U-Boot's part: what the menu does, when the BlissROM
entry appears, how BlissROM is started, and how to build, test and write v7. The partition split, the BlissROM images
and every other write are in the main guide,
[iceland-mainline/docs/DUAL-BOOT.md](https://github.com/mzakamin-hub/iceland-mainline/blob/main/docs/DUAL-BOOT.md):
follow that guide from the top. It writes v7 to `boot_b` as its last step (W6), after a RAM test (M).

Tested on the OnePlus Pad 4 with BlissROM v20.1 (iceland, build 20261016) and Fedora 44.

## What you need

| Item | Note |
|---|---|
| An unlocked bootloader and the Fedora install of [INSTALL-GUIDE.md](https://github.com/mzakamin-hub/iceland-mainline/blob/main/docs/INSTALL-GUIDE.md) | U-Boot (v4 or newer) already in `boot_b` |
| U-Boot v7: the plain image for `fastboot boot` and the AVB-footered image for `boot_b` | [Build](#build) below |
| iceland-device **0.28-25** or newer on Fedora, or 0.28-24 with `iceland.carrier=fedora` in GRUB's `iceland_args` | not U-Boot, but without it Fedora can stop in the initramfs on the dual-boot layout (main guide, W0a / W2b) |
| BlissROM's `boot.img` in `boot_a`, its slot-b boot parts (`vendor_boot_b`, `init_boot_b`, `dtbo_b`, the three `vbmeta_b`) and its system in `super` | main guide, W5b / W5k / W5c |
| `fastboot` on the PC | |

## The menu

1. ABL starts `boot_b` (U-Boot) and counts one try of slot b.
2. If ABL started in charger mode (cable power-on), there is no menu: Fedora starts. If a key is still held, there
   is no menu either.
3. Otherwise the menu shows for 5 s. Volume Up / Down move, Power selects; with no key press, Fedora starts.
   - **Fedora**: U-Boot maps the `fedora` partition when there is one (the dual-boot layout), else the Fedora disk
     image in `userdata`, and runs the EFI boot manager on it (shim, GRUB, Fedora's kernel).
   - **BlissROM**: only on the dual-boot layout, see [The gate](#the-gate).
   - **Boot loader (fastboot)**: stores the boot-loader reboot reason in the PMIC, reads it back, resets; ABL then
     stays in its fastboot and starts no slot.
4. Holding Volume Down at power-on still reaches ABL's fastboot without U-Boot.

## The gate

Before the menu, `qcom_recovery_gate scsi boot_a` decides, reading only, whether the BlissROM entry is shown. It is
open only when all of these hold:

- a `fedora` partition sits next to `userdata` on the same LUN and the two do not overlap;
- `userdata` does not start with a GPT header or a btrfs superblock (that would be the Fedora disk: Android must never
  start on it);
- `boot_a` holds an Android boot image (header v3 / v4) with an arm64 kernel.

The line `=== recovery gate: ... open ===` or `... closed ===` on the screen names the reason. On the Fedora-only
layout the gate stays closed and the menu reads Fedora / Boot loader.

## How BlissROM starts (patch 0015)

The OnePlus ABL treats U-Boot in `boot_b` as an Android boot image. Before it jumps to U-Boot it has already loaded
`vendor_boot_b` and `init_boot_b` (the ramdisks, with their bootconfig), built the device tree from `vendor_boot_b` +
`dtbo_b`, and set the verified-boot state. The BlissROM entry runs `qcom_android_chain scsi boot_a`: it loads the kernel
of the boot image in `boot_a` and boots it (`booti`) with exactly that ramdisk, device tree and ABL's kernel command
line. Android sees a normal start of slot b.

Every check comes before the kernel is read: ABL's device tree is valid and in RAM, it has bootargs and a ramdisk range,
the ramdisk starts with a cpio or compressed stream and ends with a bootconfig that has `androidboot.` values, `boot_a`
holds a v3 / v4 boot image with a kernel of 64 B to 128 MiB, the kernel's load area overlaps neither ABL's device tree
nor the ramdisk, and the kernel is an arm64 Image. The command only reads storage. If a check fails it prints
`=== android chain: <reason>: not started ===`, then `BlissROM did not start - the line above says why - Fedora in
20 s`, and Fedora starts.

Why `boot_a`: BlissROM's `boot.img` must never go into `boot_b`, which holds U-Boot. The OnePlus ABL starts
`recovery_b` only when the image there has no kernel, and then with `boot_b`'s kernel (U-Boot), so a kernel in
`recovery_b` cannot start Android. `boot_a`, on the unused slot a, only holds the kernel.

## Build

```
scripts/prepare.sh ./src && scripts/build.sh ./src ./out
```

`prepare.sh` applies `patches/0001-infiniti` and `patches/0002-iceland` (0001-0015) on the pinned upstream tag and
checks the resulting source tree against `uboot.pin` (`TREE_AFTER_0002_iceland=4f667505d646...`, the tree of the
tested v7). The plain image is `u-boot-iceland-usb.img`. A local build has another hash than the tested image (U-Boot
embeds its build time); the tested ones are listed in the [README](../README.md#install-build-patches-0004-0015).

For `boot_b` the plain image needs an AVB footer that matches the tablet's current `boot_b` (rollback index,
`os_version`, `security_patch`): see
[iceland-mainline/tools/installer/README-INSTALLER.md](https://github.com/mzakamin-hub/iceland-mainline/blob/main/tools/installer/README-INSTALLER.md).
The header values in `uboot.pin` must also match.

## Test and write

1. **RAM test, writes nothing.** In ABL's fastboot: `fastboot boot u-boot-iceland-usb.img` (the plain image). On the
   dual-boot layout the menu shows Fedora / BlissROM / Boot loader; choose BlissROM and check that it starts, then
   power on again and check Fedora.
2. **Save the current `boot_b`** if your backup does not hold it yet (the main guide's `dualboot-backup.sh` does:
   `parts/boot_b.img`).
3. **Write.** In ABL's fastboot: `fastboot flash boot_b <your footered v7 image>`. Check the file's sha256 before you
   type the command. A `boot_b` write resets slot b's flags in ABL (successful no, new retry count); the next good
   start of Fedora (`iceland-slot-mark`) or BlissROM (Android's boot control) marks it again.
4. **Check.** Power on: the menu reads Fedora / BlissROM / Boot loader, and both systems start from it. Then hold
   Volume Down at power-on and read `fastboot getvar current-slot` (`b`) and `fastboot getvar slot-successful:b`
   (`yes`).

**Undo:** `fastboot flash boot_b` with the saved `boot_b` image. If the tablet ever stops in ABL's fastboot instead of
the menu (slot b out of tries), `fastboot boot` the plain v7 and start a system from its menu: a good start marks slot
b again.

## Known limits

- BlissROM's updater must stay off: it installs into slot a and switches to it, which skips U-Boot.
- Never flash a BlissROM image into `boot_b`, never `fastboot set_active a`, and never use Settings > "Erase all
  data" in BlissROM (it leaves a wipe command in `misc` that the menu does not handle).
- Reboot to the boot loader from Linux lands in Fedora (ABL ignores it): use Volume Down at power-on or the menu's
  "Boot loader (fastboot)" entry. `fastboot reboot-bootloader` from U-Boot's own fastboot works (patch 0010).
- Writing `boot_a` resets slot a's flags in ABL, so slot a counts as bootable although it holds no system; slot b
  stays the active slot.
- BlissROM's own recovery is not reachable from the menu.
