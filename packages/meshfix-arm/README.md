# ARM mesh fix (3.14.43 APs)

Runtime patcher for the ARM `wlan.ko` used by the `ap-arm-dakota` and
`ap-arm-qca` AP families.  The same `wlan.ko` bug and the same check sequence
are present in both; one module covers them.

The patch is the same idea as the MIPS scorpion fix (found by Dan Brown in
[`dbro/zd1200`](https://github.com/dbro/zd1200); see `../meshfix/README.md`).
`ieee80211_input` checks the frame ethertype for `0x8100`, then runs a VLAN block that does:

```c
memmove(data + 2, data, 16);
skb_pull(skb, 2);
```

The patcher finds the ARM check sequence:

```
e5943118  ldr   r3, [r4, #280]
e1d330bc  ldrh  r3, [r3, #12]
e6bf3fb3  rev16 r3, r3
e6ff3073  uxth  r3, r3
e3530c81  cmp   r3, #0x8100
1a000002  bne   <skip>
```

and replaces the `bne` with `b`, skipping the block.  It requires exactly one
match and verifies the stock `0x1a000002` before writing `0xea000002`.

## Build

The module needs the 3.14.43 ARM `wlan_fils.ko` template from the AP rootfs
(`/lib/modules/3.14.43/net/wlan_fils.ko`) or from the corresponding
`ap-arm-dakota` / `ap-arm-qca` image.  The template supplies `struct module`
and the vermagic; `meshpatch-arm.c` supplies the patcher.

```sh
./build-meshpatch-arm.sh --template /path/to/wlan_fils.ko --out out
```

Requires `arm-linux-gnueabi-gcc`, `arm-linux-gnueabi-ld` and `python3`.

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

The MIPS scorpion fix is separate (`packages/meshfix`); the 4.4.60 QCA APs
(`ap-arm-cypress`, `ap-arm-11ax`) use `qca_ol.ko` and do not need this patch.
