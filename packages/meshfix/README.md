# Runtime MIPS mesh fix

Deploy the 10.5.1.0.x mesh RX fix to APs from a ZoneDirector at runtime.  The
stock signed AP firmware and the on-flash `wlan.ko` are untouched; a small
kernel module changes two bytes in the loaded `wlan.ko` text.

The bug and its fix were found by Dan Brown in
[`dbro/zd1200`](https://github.com/dbro/zd1200), which patches `wlan.ko` in
the AP firmware image (`ap_11n_scorpion_mesh_vlan_rx` in its
`binary_patch_catalog.json`).  The signature and replacement used here are
his; this package applies them at runtime instead.

## How it works

`meshpatch-sig.ko` scans the loaded `wlan` text for a 64-byte signature of the
patch site, requires exactly one match, verifies the stock branch
`0x5462000b` (`bnel`), writes `0x1000000b` (`b`), and runs `synci`.  A
different build fails `insmod` without writing; an already-patched AP returns
success without writing.  The `wlan` base and size are module parameters
supplied by the hook from `/proc/modules`:

```sh
insmod meshpatch-sig.ko wlan_base=<base> wlan_size=<size>
```

## Files

| file | purpose |
|---|---|
| `meshpatch-sig.c` | signature-scanning module source; `.ko` is built in-container |
| `wlan_fils.c` | 2.6.32 struct module/vermagic stub |
| `build-meshpatch-sig.sh`, `patch-module.py` | in-container builder |
| `hook.sh` | AP `/writable/data/scripts/start/00-zdmf-meshpatch` hook |
| `manifest.env`, `manifest.json` | module hash, kernel, signature |
| `zd-meshfix` | ZD-side driver: stage, install, status, uninstall |

## Build

The module is built in the container from `meshpatch-sig.c` and the
`wlan_fils.c` struct-module stub:

```sh
./build-meshpatch-sig.sh
```

It updates `EXPECTED_SHA` and `module_sha256` in the manifests.  The container
bootstrap and the Docker image run it when `meshpatch-sig.ko` is absent.

## Deploy

Copy `packages/meshfix/` to `/writable/zd1200-meshfix` on the ZD, then:

```sh
./zd-meshfix stage
./zd-meshfix install --all       # or --ap <mac>
./zd-meshfix status --all
./zd-meshfix uninstall --all
```

`zd-meshfix` runs on the ZD and drives each AP through `rksap_cli -s`, the
vendor shell mode.  The install command fetches the module, hook and manifest
from the ZD's TFTP server, installs the start hook, and inserts the module when
`wlan` is loaded.  The hook re-applies it after each boot.

The firmware patch `scripts/container/patches/85-meshfix-hook.sh` installs
this runtime into `/etc/zd1200-meshfix` and calls `zd-meshfix install --all`
from `meshTopologyChange()`, so a joining AP is patched at runtime.

## Safety

* `hook.running` sentinel: a previous run that did not finish disables the
  hook for one boot.
* kernel, module hash and `wlan` presence are checked before `insmod`.
* each boot records an attempt before `insmod` and confirms it after 90
  seconds; a failed `insmod` leaves stock and is retried on the next boot.
* the module verifies the stock word before writing; no match or multiple
  matches means no write.

## Caveat

The signature includes the stock bytes at the patch site, so after patching
`cleanup_module()` cannot find the site again.  `rmmod` leaves the patch in
place and a later `insmod` returns `EINVAL` until the AP reboots, which
reloads the stock `wlan.ko`.

## Firmware scope

There is no firmware-version check: the module's signature and stock-word
check decide whether a matching `wlan` is patched.  The hook still requires
kernel 2.6.32.24, a matching module hash and `wlan` loaded; a build that does
not match fails `insmod` and leaves stock.
