#!/usr/bin/env bash
#
# 85-meshfix-hook.sh - install the runtime mesh fixes and hook AP joins.
#
# Installs packages/meshfix into /etc/zd1200-meshfix (2.6.32 MIPS) and
# packages/meshfix-arm into /etc/zd1200-meshfix-arm (3.14.43 ARM), then calls
# both drivers from sys_wrapper.sh's meshTopologyChange(), where the APs are
# reachable over the APCLI.  `ZD_MESHFIX=0` skips the patch; missing runtime
# files fail it.
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../patch-lib.sh
. "$(dirname "$BASE")/patch-lib.sh"
patch_env

RUNTIME="$(cd "$BASE/../../../packages/meshfix" && pwd)"
RUNTIME_ARM="$(cd "$BASE/../../../packages/meshfix-arm" && pwd)"
RUNTIME_FILES=(zd-meshfix hook.sh manifest.env meshpatch-sig.ko)
ARM_FILES=(zd-meshfix-arm hook.sh manifest.env meshpatch-arm.ko)
TARGET="/bin/sys_wrapper.sh"
HOOK_TAG="zd-meshfix hook: topology changed"
HOOK_TAG_ARM="zd-meshfix-arm hook: topology changed"

apply() { # <name> <img>
    local name="$1" img="$2"
    local f changed=0 add_mips add_arm

    if [ "${ZD_MESHFIX:-1}" = 0 ]; then
        echo "  mesh fix disabled (ZD_MESHFIX=0)"
        return 0
    fi

    # 1. Install both runtimes.  mkdir_p records the new directories and
    #    write_local records the new files, so a patch-set rollback removes
    #    them again instead of leaving stale copies behind.
    mkdir_p "$img" "/etc/zd1200-meshfix"
    for f in "${RUNTIME_FILES[@]}"; do
        if [ ! -f "$RUNTIME/$f" ]; then
            echo "  ! $RUNTIME/$f missing" >&2
            return 1
        fi
        cp -f "$RUNTIME/$f" "$WORK/$f"
        chmod 0755 "$WORK/$f"
        write_local "$img" "/etc/zd1200-meshfix/$f" "$WORK/$f" 0755
        changed=1
    done

    mkdir_p "$img" "/etc/zd1200-meshfix-arm"
    for f in "${ARM_FILES[@]}"; do
        if [ ! -f "$RUNTIME_ARM/$f" ]; then
            echo "  ! $RUNTIME_ARM/$f missing" >&2
            return 1
        fi
        cp -f "$RUNTIME_ARM/$f" "$WORK/$f"
        chmod 0755 "$WORK/$f"
        write_local "$img" "/etc/zd1200-meshfix-arm/$f" "$WORK/$f" 0755
        changed=1
    done

    # 2. Hook meshTopologyChange(), after its closing `fi`, so the hooks run
    #    on every topology change (inside the GW_ENABLE test they would only
    #    run on gateway-enabled guests).  Each block is added once, so an
    #    upgrade from the MIPS-only hook gains the ARM block without
    #    duplicating the MIPS one.
    if ! fs_read "$img" "$TARGET" "$WORK/sys_wrapper.sh.orig"; then
        echo "  ! $TARGET missing on $name" >&2
        return 1
    fi
    add_mips=1
    if grep -q "$HOOK_TAG" "$WORK/sys_wrapper.sh.orig"; then add_mips=0; fi
    add_arm=1
    if grep -q "$HOOK_TAG_ARM" "$WORK/sys_wrapper.sh.orig"; then add_arm=0; fi
    if [ "$add_mips" = 1 ] || [ "$add_arm" = 1 ]; then
        awk -v tag="$HOOK_TAG" -v tag_arm="$HOOK_TAG_ARM" \
            -v add_mips="$add_mips" -v add_arm="$add_arm" '
            /brctl setpififmode br1 wlan63 1/ {
                print
                if ((getline line) > 0) print line   # the closing `fi`
                if (add_mips == 1) {
                    print "\t# " tag ": APs are reachable over the APCLI"
                    print "\tmkdir -p /writable/zd1200-meshfix 2>/dev/null"
                    print "\t[ -x /etc/zd1200-meshfix/zd-meshfix ] && /etc/zd1200-meshfix/zd-meshfix install --all >> /writable/zd1200-meshfix/topology.log 2>&1 &"
                }
                if (add_arm == 1) {
                    print "\t# " tag_arm ": ARM APs are reachable over the APCLI"
                    print "\tmkdir -p /writable/zd1200-meshfix-arm 2>/dev/null"
                    print "\t[ -x /etc/zd1200-meshfix-arm/zd-meshfix-arm ] && /etc/zd1200-meshfix-arm/zd-meshfix-arm install --all >> /writable/zd1200-meshfix-arm/topology.log 2>&1 &"
                }
                next
            }
            { print }
        ' "$WORK/sys_wrapper.sh.orig" > "$WORK/sys_wrapper.sh.new"
        if cmp -s "$WORK/sys_wrapper.sh.orig" "$WORK/sys_wrapper.sh.new"; then
            echo "  ! could not find the meshTopologyChange() anchor in $TARGET" >&2
            return 1
        fi
        echo "  change to $TARGET:"
        diff -u "$WORK/sys_wrapper.sh.orig" "$WORK/sys_wrapper.sh.new" | sed 's/^/    /' || true
        write_local "$img" "$TARGET" "$WORK/sys_wrapper.sh.new"
        changed=1
    else
        echo "  $TARGET already carries both meshfix hooks"
    fi

    PATCH_APPLIED=$changed
}

verify() { # <name> <img>
    local name="$1" img="$2"
    if ! fs_read "$img" "$TARGET" "$WORK/sys_wrapper.verify" \
       || ! grep -q "$HOOK_TAG" "$WORK/sys_wrapper.verify" \
       || ! grep -q "$HOOK_TAG_ARM" "$WORK/sys_wrapper.verify"; then
        echo "FAIL $name: $TARGET lacks the meshfix hooks" >&2
        return 1
    fi
    if ! fs_read "$img" "/etc/zd1200-meshfix/zd-meshfix" "$WORK/zd-meshfix.verify"; then
        echo "FAIL $name: /etc/zd1200-meshfix/zd-meshfix missing" >&2
        return 1
    fi
    if ! fs_read "$img" "/etc/zd1200-meshfix-arm/zd-meshfix-arm" "$WORK/zd-meshfix-arm.verify"; then
        echo "FAIL $name: /etc/zd1200-meshfix-arm/zd-meshfix-arm missing" >&2
        return 1
    fi
    echo "OK   $name: meshfix runtime + hook installed (MIPS + ARM)"
    return 0
}

patch_main apply verify
