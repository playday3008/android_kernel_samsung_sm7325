#!/bin/bash
# Build one device from a kernel source tree.
#
#   build.sh <device> <srcdir> <outdir>
#
# Requires CLANG to point at an extracted AOSP clang prebuilt.
set -euo pipefail

DEVICE=$1
SRC=$(readlink -f "$2")
OUT=$(readlink -f "$3")
CI_ROOT=$(readlink -f "$(dirname "$0")/..")

# shellcheck disable=SC1090
. "$CI_ROOT/devices/$DEVICE/meta.env"

# clang must be in PATH before the defconfig step, or CC_IS_CLANG stays unset
# and every LTO/CFI option silently disappears from .config.
export PATH="$CLANG/bin:$PATH"
export KBUILD_BUILD_USER=ci
export KBUILD_BUILD_HOST=github

# CROSS_COMPILE is required even with LLVM=1; without it clang targets the host
# and dies on "unknown register name 'x0' in asm".
MAKE_ARGS=(
	ARCH=arm64
	CC=clang
	LLVM=1
	LLVM_IAS=1
	CROSS_COMPILE=aarch64-linux-gnu-
	CONFIG_SECTION_MISMATCH_WARN_ONLY=y
	"O=$OUT"
)

cd "$SRC"
mkdir -p "$OUT"

echo "::group::defconfig $DEFCONFIG"
clang --version | head -1
make "${MAKE_ARGS[@]}" "$DEFCONFIG"
cp "$OUT/.config" "$OUT/config.saved"
echo "::endgroup::"

echo "::group::build"
make -j"$(nproc)" "${MAKE_ARGS[@]}"
echo "::endgroup::"

ls -l "$OUT/arch/arm64/boot/Image"
