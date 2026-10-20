#!/bin/sh
#
# build-meshpatch-arm.sh - build meshpatch-arm.ko for the 3.14.43 ARM APs.
#
# wlan_fils.c supplies struct module, .modinfo and the 3.14.43 vermagic, so
# the default build needs no vendor wlan_fils.ko.  meshpatch-arm.c supplies
# the patcher.  One module covers ap-arm-dakota and ap-arm-qca.
#
# Usage: ./build-meshpatch-arm.sh [--template wlan_fils.ko] [--out DIR]
#
# --template builds against a vendor wlan_fils.ko instead of the stub; it is
# kept for comparing against a stock AP template.
#
# Requires arm-linux-gnueabi-gcc and arm-linux-gnueabi-ld; --template also
# needs python3.
set -eu

BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STUB=$BASE/wlan_fils.c
TEMPLATE=
OUT=$BASE

while [ $# -gt 0 ]; do
    case "$1" in
        --template) TEMPLATE=$2; shift 2 ;;
        --out)      OUT=$2; shift 2 ;;
        -h|--help)  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

CC=${CC:-arm-linux-gnueabi-gcc}
LD=${LD:-arm-linux-gnueabi-ld}
command -v "$CC" >/dev/null 2>&1 || { echo "error: $CC not found" >&2; exit 1; }
command -v "$LD" >/dev/null 2>&1 || { echo "error: $LD not found" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/meshpatch-arm.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

"$CC" -c -O2 -march=armv7-a -marm -mfloat-abi=soft \
    -fno-pic -fno-stack-protector -ffreestanding \
    -fno-unwind-tables -fno-asynchronous-unwind-tables \
    -o "$WORK/meshpatch-arm.o" "$BASE/meshpatch-arm.c"

if [ -n "$TEMPLATE" ]; then
    [ -f "$TEMPLATE" ] || { echo "error: template not found: $TEMPLATE" >&2; exit 1; }
    "$LD" -r -o "$WORK/meshpatch-arm.ko" "$TEMPLATE" "$WORK/meshpatch-arm.o"
    python3 "$BASE/patch-module-arm.py" "$WORK/meshpatch-arm.ko" "$WORK/meshpatch-arm.patched.ko"
    BUILT=$WORK/meshpatch-arm.patched.ko
else
    [ -f "$STUB" ] || { echo "error: stub not found: $STUB" >&2; exit 1; }
    "$CC" -c -O2 -march=armv7-a -marm -mfloat-abi=soft \
        -fno-pic -fno-stack-protector -ffreestanding \
        -fno-unwind-tables -fno-asynchronous-unwind-tables \
        -o "$WORK/wlan_fils.o" "$STUB"
    "$LD" -r -o "$WORK/meshpatch-arm.ko" "$WORK/wlan_fils.o" "$WORK/meshpatch-arm.o"
    BUILT=$WORK/meshpatch-arm.ko
fi

mkdir -p "$OUT"
cp -f "$BUILT" "$OUT/meshpatch-arm.ko"
if [ "$OUT" != "$BASE" ]; then
    cp -f "$BASE/manifest.env" "$OUT/manifest.env"
fi

sha=$(sha256sum "$OUT/meshpatch-arm.ko" | awk '{print $1}')
sed -i "s/^EXPECTED_SHA=.*/EXPECTED_SHA=$sha/" "$OUT/manifest.env"

echo "built $OUT/meshpatch-arm.ko ($sha)"
