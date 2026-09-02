#!/bin/bash
# Build a flashable AnyKernel3 zip around an already-built Image.
#
#   pack_anykernel.sh <device> <image> <kernel-release> <zip>
set -euo pipefail

DEVICE=$1
IMAGE=$(readlink -f "$2")
KERNEL_RELEASE=$3
ZIP=$(readlink -f "$4")
CI_ROOT=$(readlink -f "$(dirname "$0")/..")

# shellcheck disable=SC1090
. "$CI_ROOT/devices/$DEVICE/meta.env"

: "${ANYKERNEL_REF:?set ANYKERNEL_REF to an AnyKernel3 commit}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
AK3="$WORK/ak3"

git init -q "$AK3"
git -C "$AK3" fetch -q --depth 1 https://github.com/osm0sis/AnyKernel3 "$ANYKERNEL_REF"
git -C "$AK3" checkout -q FETCH_HEAD
rm -rf "$AK3/.git" "$AK3/.github" "$AK3/README.md" "$AK3/LICENSE"

names=""
index=1
for name in $ANYKERNEL_DEVICES; do
	names="$names${names:+\\n}device.name$index=$name"
	index=$((index + 1))
done

sed -e "s|@KERNEL_STRING@|$KERNEL_RELEASE|" \
    -e "s|@DEVICE_NAMES@|$names|" \
    "$CI_ROOT/scripts/anykernel.sh.in" > "$AK3/anykernel.sh"

cp "$IMAGE" "$AK3/Image"
(cd "$AK3" && zip -qr9 "$ZIP" .)
unzip -p "$ZIP" anykernel.sh | sed -n '1,12p'
