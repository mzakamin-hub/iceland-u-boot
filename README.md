# iceland-u-boot

U-Boot for the OnePlus Pad 4 (`iceland`, SM8850P), chainloaded by the stock OnePlus ABL — the same boot path
as the OnePlus 15 (infiniti-mainline). Kept as a patch queue on an upstream tag; every commit keeps its author.

| Path | Content |
|---|---|
| `uboot.pin` | upstream tag, infiniti commit, expected tree hashes, mkbootimg pin, boot header values |
| `patches/0001-infiniti/` | infiniti-mainline/u-boot `main` (14 commits: Kaanapali clocks, eUSB2, PMIC arb v8, ABL memory map pass-through, EFI from userdata, OnePlus 15) |
| `patches/0002-iceland/` | OnePlus Pad 4 board (DTS, `iceland_defconfig`, `iceland.env`) |
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
