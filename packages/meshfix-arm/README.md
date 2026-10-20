# ARM mesh fix (3.14.43 APs)

Runtime patcher for the ARM `wlan.ko` used by the `ap-arm-dakota` and
`ap-arm-qca` AP families.  The same `wlan.ko` bug and the same check sequence
are present in the ZoneDirector 10.5.1.x and the SmartZone 5.2.2 AP images;
one module covers both.

The patch is the same idea as the MIPS scorpion fix (found by Dan Brown in
[`dbro/zd1200`](https://github.com/dbro/zd1200); see `../meshfix/README.md`).
`ieee80211_input` checks the frame ethertype for `0x8100`, then runs a VLAN block that does:

```c
memmove(data + 2, data, 16);
skb_pull(skb, 2);
```

The patcher finds the ARM check sequence:

```
e5943118  ldr   r3, [r4, #280]     ; ZoneDirector 10.5.1.x
e5963124  ldr   r3, [r6, #292]     ; SmartZone 5.2.2
e1d330bc  ldrh  r3, [r3, #12]
e6bf3fb3  rev16 r3, r3
e6ff3073  uxth  r3, r3
e3530c81  cmp   r3, #0x8100
1a000002  bne   <skip>
```

Both builds have the same `ldrh`/`rev16`/`uxth`/`cmp`/`bne` tail; only the
`ldr` differs because `struct sk_buff` moved by 12 bytes.  The patcher accepts
either first word, replaces the `bne` with `b`, requires exactly one match in
total, and verifies the stock `0x1a000002` before writing `0xea000002`.

## Build

`wlan_fils.c` supplies `struct module`, `.modinfo` and the 3.14.43 vermagic
(`3.14.43 SMP mod_unload ARMv7 p2v8`), so the default build needs no vendor
file.  `meshpatch-arm.c` supplies the patcher.

```sh
./build-meshpatch-arm.sh --out out
```

`--template /path/to/wlan_fils.ko` builds against a vendor template instead of
the stub, for an AP build that rejects the stub's vermagic.  Both installers
build the module automatically.

Requires `arm-linux-gnueabi-gcc` and `arm-linux-gnueabi-ld`; the `--template`
path also needs `python3`.

## Test

Copy `meshpatch-arm.ko`, `hook.sh` and `manifest.env` to the AP's
`/writable/zd1200-meshfix-arm`, then:

```sh
cd /writable/zd1200-meshfix-arm
base=$(awk '/^wlan /{print $6}' /proc/modules)
size=$(awk '/^wlan /{print $2}' /proc/modules)
insmod ./meshpatch-arm.ko wlan_base=$base wlan_size=$size
lsmod | grep '^meshpatch '
```

For boot persistence, copy `hook.sh` to
`/writable/data/scripts/start/00-zdmf-meshpatch-arm`.

## SmartZone 5.2.2 APs

The SmartZone 5.2.2.0.2122 AP bundle carries the bug in its two ARM 3.14.43
images (`R510/R320` and `R710/R720`).  Its MIPS scorpion image
(`T300/.../R500/R600/R310`) does not have the destructive block; the MIPS
module no-ops there.

The hook and module live under `/writable`, which the AP firmware does not
clear on a factory reset or a firmware upgrade (verify on your model).  That
lets a SmartZone AP be patched first by a ZoneDirector and then moved to
SmartZone:

1. Let the AP join the ZoneDirector once so `meshTopologyChange()` runs
   `zd-meshfix-arm install --all` (or run it by hand).
2. Check `zd-meshfix-arm status --all` for `meshpatch` and the confirmed
   state.
3. Move the AP to SmartZone.  The start hook
   (`/writable/data/scripts/start/00-zdmf-meshpatch-arm`) re-applies the
   patch on each boot.

A later SmartZone build with a different `wlan.ko` will fail the signature
match; the hook logs it in `/writable/zd1200-meshfix-arm/hook.log` and leaves
the stock module in place.

## Firmware scope

There is no firmware-version check: the signatures and the stock-word check
decide whether a matching `wlan` is patched.  A build that does not match
fails `insmod` and leaves stock.  The MIPS scorpion fix is separate
(`packages/meshfix`); the 4.4.60 QCA APs (`ap-arm-cypress`, `ap-arm-11ax`) use
`qca_ol.ko` and do not need this patch.
