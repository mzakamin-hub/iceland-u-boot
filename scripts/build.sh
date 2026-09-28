#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build U-Boot for the OnePlus Pad 4 and wrap it as Android boot images for ABL chainloading.
#   scripts/build.sh [SRC_DIR] [OUT_DIR]      (defaults: ./src ./out)
# Output OUT_DIR/dist/:
#   u-boot-iceland-v4.img  header v4 (stock format), kernel = gzip(u-boot.bin): U-Boot + its DT, so the DT
#                          sits right after U-Boot once ABL decompresses it. Verified on the tablet
#                          (diagnostic run 3). A DT appended *after* the gzip stream is dropped by ABL.
#   u-boot-iceland-v2.img  header v2 with the DT in the header (alternative, not needed so far)
#   u-boot.bin.gz, u-boot.dtb, BUILD_INFO, SHA256SUMS
# First test is always a RAM boot (`fastboot boot <img>`): nothing is written to the tablet.
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
src=$(realpath "${1:-$top/src}")
out=$(realpath -m "${2:-$top/out}")
# shellcheck source=../uboot.pin
. "$top/uboot.pin"
cross=${CROSS_COMPILE:-aarch64-linux-gnu-}
mk() { make -C "$src" O="$out" CROSS_COMPILE="$cross" -j"${JOBS:-$(nproc)}" "$@"; }

mk iceland_defconfig
mk
dist=$out/dist; rm -rf "$dist"; mkdir -p "$dist"
cmp -s "$out/u-boot.bin" <(cat "$out/u-boot-nodtb.bin" "$out/u-boot.dtb") || { echo "u-boot.bin is not u-boot-nodtb.bin + DT"; exit 1; }
gzip -9nc "$out/u-boot.bin" > "$dist/u-boot.bin.gz"
gzip -9nc "$out/u-boot-nodtb.bin" > "$out/u-boot-nodtb.bin.gz"
cp "$out/u-boot.dtb" "$dist/"

tools=$out/mkbootimg
if [ ! -d "$tools/.git" ]; then
	git clone -q "$MKBOOTIMG_URL" "$tools"
fi
git -C "$tools" checkout -q "$MKBOOTIMG_COMMIT"
python3 "$tools/mkbootimg.py" --header_version 4 \
	--kernel "$dist/u-boot.bin.gz" \
	--os_version "$BOOT_OS_VERSION" --os_patch_level "$BOOT_OS_PATCH_LEVEL" \
	--output "$dist/u-boot-iceland-v4.img"
python3 "$tools/mkbootimg.py" --header_version 2 --pagesize 4096 --base 0x80000000 \
	--kernel_offset 0x00008000 --kernel "$out/u-boot-nodtb.bin.gz" \
	--dtb_offset 0x01f00000 --dtb "$out/u-boot.dtb" \
	--os_version "$BOOT_OS_VERSION" --os_patch_level "$BOOT_OS_PATCH_LEVEL" \
	--output "$dist/u-boot-iceland-v2.img"
{
	echo "u-boot-commit: $(git -C "$src" rev-parse HEAD)"
	echo "patch-queue-commit: $(git -C "$top" rev-parse HEAD 2>/dev/null || echo unknown)"
	echo "compiler: $(${cross}gcc --version | head -n1)"
	echo "mkbootimg: $MKBOOTIMG_COMMIT"
	echo "boot header: os_version $BOOT_OS_VERSION, os_patch_level $BOOT_OS_PATCH_LEVEL"
	echo "date: $(date -u +%FT%TZ)"
} > "$dist/BUILD_INFO"
(cd "$dist" && sha256sum -- * > SHA256SUMS)
echo "built -> $dist"
