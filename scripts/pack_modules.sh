#!/bin/bash
# Produce a vendor-modules.tar.gz whose layout matches what the ROM expects
# under /vendor/lib/modules.
#
#   pack_modules.sh <device> <srcdir> <outdir> <tarball>
set -euo pipefail

DEVICE=$1
SRC=$(readlink -f "$2")
OUT=$(readlink -f "$3")
TARBALL=$(readlink -f "$4")
CI_ROOT=$(readlink -f "$(dirname "$0")/..")

# shellcheck disable=SC1090
. "$CI_ROOT/devices/$DEVICE/meta.env"

export PATH="$CLANG/bin:$PATH"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

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
make "${MAKE_ARGS[@]}" INSTALL_MOD_PATH="$STAGE/install" modules_install >/dev/null

RELEASE=$(cat "$OUT/include/config/kernel.release")
FLAT="$STAGE/depmod/lib/modules/$RELEASE"
mkdir -p "$FLAT"
find "$STAGE/install" -name '*.ko' -exec cp -t "$FLAT" {} +

# The ROM ships some modules under different filenames than the kernel builds
# them; modules.load is written against the ROM's names, so rename before depmod.
for rename in ${MODULE_RENAMES:-}; do
	from=${rename%%=*}
	to=${rename#*=}
	[ -e "$FLAT/$from" ] || continue
	mv "$FLAT/$from" "$FLAT/$to"
done

llvm-strip --strip-debug "$FLAT"/*.ko
depmod -b "$STAGE/depmod" "$RELEASE"

DEST="$STAGE/tar/lib/modules"
mkdir -p "$DEST"
cp "$FLAT"/*.ko "$DEST"
# depmod writes paths relative to lib/modules/$RELEASE; the ROM's modules.dep
# uses absolute /vendor/lib/modules paths instead.
sed -E 's#(^|[[:space:]:])([^[:space:]:]*/)?([^[:space:]:/]+\.ko)#\1/vendor/lib/modules/\3#g' \
	"$FLAT/modules.dep" > "$DEST/modules.dep"
cp "$FLAT/modules.alias" "$FLAT/modules.softdep" "$DEST"

if [ -f "$CI_ROOT/devices/$DEVICE/modules.load" ]; then
	cp "$CI_ROOT/devices/$DEVICE/modules.load" "$DEST/modules.load"
else
	echo "::notice::$DEVICE has no ROM modules.load, deriving load order from depmod"
	sed 's#^/vendor/lib/modules/##; s#\.ko:.*##' "$DEST/modules.dep" > "$DEST/modules.load"
fi

tar czf "$TARBALL" -C "$STAGE/tar" lib
tar tzf "$TARBALL" | grep -c '\.ko$' | xargs echo "modules packed:"
