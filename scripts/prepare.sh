#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the iceland U-Boot source tree: upstream tag + patches/*/ applied in order with `git am`,
# so every commit keeps its original author, date and message.
#
#   scripts/prepare.sh [SRC_DIR]     (default: ./src)
#
# Checks: upstream commit matches uboot.pin; after each series the tree hash must equal the
# TREE_AFTER_<series> value in uboot.pin (proves the queue reproduces the sources exactly).
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
src=${1:-$top/src}
# shellcheck source=../uboot.pin
. "$top/uboot.pin"

if [ ! -d "$src/.git" ]; then
	git clone --depth 1 --branch "$UPSTREAM_TAG" "$UPSTREAM_URL" "$src"
fi
cd "$src"
got=$(git rev-parse "$UPSTREAM_TAG^{commit}" 2>/dev/null || git rev-parse HEAD)
[ "$got" = "$UPSTREAM_COMMIT" ] || { echo "upstream commit $got != pinned $UPSTREAM_COMMIT"; exit 1; }
git checkout -q -B iceland "$UPSTREAM_COMMIT"
git -c user.name=prepare -c user.email=prepare@localhost am -q --abort 2>/dev/null || true

for series in "$top"/patches/*/; do
	name=$(basename "$series")
	n=$(ls "$series"*.patch 2>/dev/null | wc -l)
	[ "$n" -gt 0 ] || continue
	echo "applying $name ($n patches)"
	# committer = whoever runs the build; author/date/message come from the patch
	git -c user.name="${GIT_COMMITTER_NAME:-iceland-build}" -c user.email="${GIT_COMMITTER_EMAIL:-build@localhost}" \
		am -q --keep-cr --committer-date-is-author-date "$series"*.patch
	var="TREE_AFTER_$(echo "$name" | tr -c 'A-Za-z0-9_\n' '_')"
	want=${!var:-}
	if [ -n "$want" ]; then
		tree=$(git rev-parse HEAD^{tree})
		[ "$tree" = "$want" ] || { echo "tree after $name is $tree, expected $want"; exit 1; }
		echo "  tree matches $var"
	fi
done
echo "source ready: $src ($(git rev-parse --short HEAD))"
