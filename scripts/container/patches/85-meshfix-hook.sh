#!/usr/bin/env bash
#
# 85-meshfix-hook.sh - install the runtime mesh fix and hook AP joins.
#
# Installs packages/meshfix into /etc/zd1200-meshfix and calls
# `zd-meshfix install --all` from sys_wrapper.sh's meshTopologyChange(), where
# an AP is reachable over the APCLI.  `ZD_MESHFIX=0` skips the patch; missing
# runtime files fail it.
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../patch-lib.sh
. "$(dirname "$BASE")/patch-lib.sh"
patch_env

RUNTIME="$(cd "$BASE/../../../packages/meshfix" && pwd)"
RUNTIME_FILES=(zd-meshfix hook.sh manifest.env meshpatch-sig.ko)
TARGET="/bin/sys_wrapper.sh"
HOOK_TAG="zd-meshfix hook: topology changed"

apply() { # <name> <img>
    local name="$1" img="$2"
    local f changed=0

    if [ "${ZD_MESHFIX:-1}" = 0 ]; then
        echo "  mesh fix disabled (ZD_MESHFIX=0)"
        return 0
    fi

    # 1. Install the runtime.  mkdir_p records the new directory and
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

    # 2. Hook meshTopologyChange(), after its closing `fi`, so the hook runs
    #    on every topology change (inside the GW_ENABLE test it would only run
    #    on gateway-enabled guests).
    if ! fs_read "$img" "$TARGET" "$WORK/sys_wrapper.sh.orig"; then
        echo "  ! $TARGET missing on $name" >&2
        return 1
    fi
    if grep -q "$HOOK_TAG" "$WORK/sys_wrapper.sh.orig"; then
        echo "  $TARGET already carries the meshfix hook"
    else
        awk -v tag="$HOOK_TAG" '
            /brctl setpififmode br1 wlan63 1/ {
                print
                if ((getline line) > 0) print line   # the closing `fi`
                print "\t# " tag ": APs are reachable over the APCLI"
                print "\tmkdir -p /writable/zd1200-meshfix 2>/dev/null"
                print "\t[ -x /etc/zd1200-meshfix/zd-meshfix ] && /etc/zd1200-meshfix/zd-meshfix install --all >> /writable/zd1200-meshfix/topology.log 2>&1 &"
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
    fi

    PATCH_APPLIED=$changed
}

verify() { # <name> <img>
    local name="$1" img="$2"
    if ! fs_read "$img" "$TARGET" "$WORK/sys_wrapper.verify" \
       || ! grep -q "$HOOK_TAG" "$WORK/sys_wrapper.verify"; then
        echo "FAIL $name: $TARGET lacks the meshfix hook" >&2
        return 1
    fi
    if ! fs_read "$img" "/etc/zd1200-meshfix/zd-meshfix" "$WORK/zd-meshfix.verify"; then
        echo "FAIL $name: /etc/zd1200-meshfix/zd-meshfix missing" >&2
        return 1
    fi
    echo "OK   $name: meshfix runtime + hook installed"
    return 0
}

patch_main apply verify
