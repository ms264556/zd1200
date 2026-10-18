#!/bin/sh
#
# build-meshpatch-arm.sh - build meshpatch-arm.ko for the 3.14.43 ARM APs.
#
# The vendor wlan_fils.ko template from the AP rootfs supplies struct module
# and the 3.14.43 vermagic; meshpatch-arm.c supplies the patcher.  One module
# covers ap-arm-dakota and ap-arm-qca.
#
# Usage: ./build-meshpatch-arm.sh --template wlan_fils.ko [--out DIR]
#
# Requires arm-linux-gnueabi-gcc, arm-linux-gnueabi-ld and python3.
set -eu

BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE=
OUT=$BASE

while [ $# -gt 0 ]; do
    case "$1" in
        --template) TEMPLATE=$2; shift 2 ;;
        --out)      OUT=$2; shift 2 ;;
        -h|--help)  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

CC=${CC:-arm-linux-gnueabi-gcc}
LD=${LD:-arm-linux-gnueabi-ld}
command -v "$CC" >/dev/null 2>&1 || { echo "error: $CC not found" >&2; exit 1; }
command -v "$LD" >/dev/null 2>&1 || { echo "error: $LD not found" >&2; exit 1; }
[ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ] || { echo "error: --template wlan_fils.ko required" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/meshpatch-arm.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

"$CC" -c -O2 -march=armv7-a -marm -mfloat-abi=soft \
    -fno-pic -fno-stack-protector -ffreestanding \
    -fno-unwind-tables -fno-asynchronous-unwind-tables \
    -o "$WORK/meshpatch-arm.o" "$BASE/meshpatch-arm.c"

"$LD" -r -o "$WORK/meshpatch-arm.ko" "$TEMPLATE" "$WORK/meshpatch-arm.o"
python3 "$BASE/patch-module-arm.py" "$WORK/meshpatch-arm.ko" "$WORK/meshpatch-arm.patched.ko"

mkdir -p "$OUT"
cp -f "$WORK/meshpatch-arm.patched.ko" "$OUT/meshpatch-arm.ko"
if [ "$OUT" != "$BASE" ]; then
    cp -f "$BASE/manifest.env" "$OUT/manifest.env"
fi

sha=$(sha256sum "$OUT/meshpatch-arm.ko" | awk '{print $1}')
sed -i "s/^EXPECTED_SHA=.*/EXPECTED_SHA=$sha/" "$OUT/manifest.env"

echo "built $OUT/meshpatch-arm.ko ($sha)"
