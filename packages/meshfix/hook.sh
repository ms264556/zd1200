#!/bin/sh
# AP start hook: load meshpatch-sig.ko after wlan.ko is loaded.
#
# A sentinel guards against a previous run that did not finish; the kernel,
# module hash and wlan presence are checked; and the live wlan base/size are
# passed as module parameters.  A trial is confirmed only after 90 s with the
# module and wlan still loaded; an unconfirmed trial leaves stock.
BASE=/writable/zd1200-meshfix
SENTINEL=$BASE/hook.running
STATE=$BASE/state
LOG=$BASE/hook.log
MODULE=$BASE/meshpatch-sig.ko
MANIFEST=$BASE/manifest.env

EXPECTED_SHA=
EXPECTED_KERNEL=2.6.32.24

mkdir -p "$BASE"
if [ -e "$SENTINEL" ]; then
    echo "=== $(date) sentinel present: previous hook run did not finish; skipping" >> "$LOG"
    exit 0
fi
touch "$SENTINEL"
busybox sync 2>/dev/null || true

log() { echo "$*" >> "$LOG"; }

if [ -f "$MANIFEST" ]; then
    # shellcheck disable=SC1090
    . "$MANIFEST"
fi
EXPECTED_KERNEL=${EXPECTED_KERNEL:-2.6.32.24}

if [ "$(uname -r)" != "$EXPECTED_KERNEL" ]; then
    log "=== $(date) kernel $(uname -r) != $EXPECTED_KERNEL; leaving stock"
    rm -f "$SENTINEL"
    exit 0
fi

if [ ! -f "$MODULE" ] || [ -z "$EXPECTED_SHA" ]; then
    log "=== $(date) $MODULE or manifest hash missing; leaving stock"
    rm -f "$SENTINEL"
    exit 0
fi

if ! echo "$EXPECTED_SHA  $MODULE" | sha256sum -c - >/dev/null 2>&1; then
    log "=== $(date) meshpatch-sig.ko hash mismatch; leaving stock"
    rm -f "$SENTINEL"
    exit 0
fi

if ! grep -q '^wlan ' /proc/modules 2>/dev/null; then
    log "=== $(date) wlan not loaded at hook time; leaving stock"
    rm -f "$SENTINEL"
    exit 0
fi

wlan_line=$(grep '^wlan ' /proc/modules 2>/dev/null)
base=$(echo "$wlan_line" | awk '{print $6}')
size=$(echo "$wlan_line" | awk '{print $2}')
if [ -z "$base" ] || [ -z "$size" ]; then
    log "=== $(date) wlan base/size missing (base=$base size=$size); leaving stock"
    rm -f "$SENTINEL"
    exit 0
fi

if lsmod 2>/dev/null | grep -q '^meshpatch '; then
    log "=== $(date) meshpatch already loaded; nothing to do"
    rm -f "$SENTINEL"
    exit 0
fi

# One-shot trial guard.  confirmed=0/attempts>=1 means a previous boot loaded
# the module but never reached the confirmation check: leave stock this time.
confirmed=0
attempts=0
if [ -f "$STATE" ]; then
    # shellcheck disable=SC1090
    . "$STATE" 2>/dev/null || true
fi
if [ "$confirmed" != 1 ] && [ "$attempts" -ge 1 ] 2>/dev/null; then
    log "=== $(date) previous trial did not confirm (confirmed=$confirmed attempts=$attempts); leaving stock"
    rm -f "$SENTINEL"
    exit 0
fi

attempts=$((attempts + 1))
{ echo "confirmed=0"; echo "attempts=$attempts"; } > "$STATE"
busybox sync 2>/dev/null || true

log "=== $(date) loading $MODULE (attempt $attempts, wlan base $base size $size)"
insmod "$MODULE" "wlan_base=$base" "wlan_size=$size" >> "$LOG" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    log "insmod failed rc=$rc; leaving stock"
    # A clean insmod failure did not patch anything; allow a retry next boot.
    { echo "confirmed=0"; echo "attempts=0"; } > "$STATE"
    rm -f "$SENTINEL"
    busybox sync 2>/dev/null || true
    exit 0
fi

log "insmod ok; starting confirmation check"
(
    sleep 90
    if lsmod 2>/dev/null | grep -q '^meshpatch ' && grep -q '^wlan ' /proc/modules 2>/dev/null; then
        { echo "confirmed=1"; echo "attempts=1"; } > "$STATE"
        log "confirmed at $(date)"
    else
        log "NOT confirmed at $(date): meshpatch or wlan missing"
    fi
    busybox sync 2>/dev/null || true
) &

rm -f "$SENTINEL"
busybox sync 2>/dev/null || true
exit 0
