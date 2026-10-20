# Payload packages

The self-contained payloads this project ships into the appliance, one directory
per package. The Docker flow builds them in `docker/Dockerfile` stages; the LXC
flow builds them inside the CT via
`scripts/container/proxmox/zd1200-ct-bootstrap.sh`. Either way they are installed
by the ordered rootfs patches or by the guest-disk builder.

| package | what it is | installed by |
|---|---|---|
| `analytics/` | the Network Monitor web page, its guest collectors and the i386 helper sources | `scripts/container/patches/50-network-monitor.sh` |
| `dropbear/` | patches and build script for the optional static musl dropbear (public-key root SSH on TCP 2222) | `scripts/container/patches/60-dropbear-static.sh` |
| `meshfix/` | runtime MIPS mesh fix: signature module, AP hook and ZD driver | `scripts/container/patches/85-meshfix-hook.sh` |
| `meshfix-arm/` | runtime ARM 3.14.43 mesh fix (ZoneDirector 10.5.1.x and SmartZone 5.2.2): module, AP hook and ZD driver | `scripts/container/patches/85-meshfix-hook.sh` |

`analytics` and `dropbear` are compiled (i386/static/musl and a musl cross-build
respectively), so their build stages produce the binaries the patches install.
`meshfix` and `meshfix-arm` ship a module and a builder; both are built from
their `wlan_fils.c` stubs (the ARM builder also accepts a vendor `wlan_fils.ko`
with `--template`). The LXC bootstrap builds them when absent; the Docker image
builds them in its stages.

See each directory's `README.md` for detail. Upstream provenance and licensing
are noted there.
