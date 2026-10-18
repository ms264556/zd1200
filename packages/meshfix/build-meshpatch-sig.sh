#!/bin/sh
#
# build-meshpatch-sig.sh - build meshpatch-sig.ko from meshpatch-sig.c.
#
# Builds the struct module, .modinfo and vermagic from the wlan_fils.c stub,
# so no vendor wlan_fils.ko is needed.  Mirrors the dropbear builder: it runs
# in the container when the .ko is absent and leaves the manifest hashes behind.
#
# Usage: ./build-meshpatch-sig.sh [--out DIR]
#
# Requires mips-linux-gnu-gcc, mips-linux-gnu-ld and python3.
set -eu

BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STUB=$BASE/wlan_fils.c
OUT=$BASE

while [ $# -gt 0 ]; do
    case "$1" in
        --out)      OUT=$2; shift 2 ;;
        -h|--help)  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

CC=${CC:-mips-linux-gnu-gcc}
LD=${LD:-mips-linux-gnu-ld}
command -v "$CC" >/dev/null 2>&1 || { echo "error: $CC not found" >&2; exit 1; }
command -v "$LD" >/dev/null 2>&1 || { echo "error: $LD not found" >&2; exit 1; }
[ -f "$STUB" ] || { echo "error: stub not found: $STUB" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/meshpatch-sig.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

"$CC" -c -O2 -mabi=32 -march=mips32r2 -EB -mno-abicalls -fno-pic -G0 \
    -fno-stack-protector -o "$WORK/wlan_fils.o" "$STUB"

"$CC" -c -O2 -mabi=32 -march=mips32r2 -EB -mno-abicalls -fno-pic -G0 \
    -fno-stack-protector \
    -Dinit_module=meshpatch_init -Dcleanup_module=meshpatch_cleanup \
    -o "$WORK/meshpatch-sig.o" "$BASE/meshpatch-sig.c"

"$LD" -r -o "$WORK/meshpatch-sig.ko" "$WORK/wlan_fils.o" "$WORK/meshpatch-sig.o"
python3 "$BASE/patch-module.py" "$WORK/meshpatch-sig.ko"

mkdir -p "$OUT"
cp -f "$WORK/meshpatch-sig.ko" "$OUT/meshpatch-sig.ko"

sha=$(sha256sum "$OUT/meshpatch-sig.ko" | awk '{print $1}')
sed -i "s/^EXPECTED_SHA=.*/EXPECTED_SHA=$sha/" "$OUT/manifest.env"
python3 - "$OUT/manifest.json" "$sha" <<'PY'
import json
import sys

path, sha = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh)
data["module_sha256"] = sha
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY

echo "built $OUT/meshpatch-sig.ko ($sha)"
