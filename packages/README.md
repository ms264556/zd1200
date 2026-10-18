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
| `meshfix/` | runtime ap-11n-scorpion mesh fix: signature module, AP hook and ZD driver | `scripts/container/patches/85-meshfix-hook.sh` |

`analytics` and `dropbear` are compiled (i386/static/musl and a musl cross-build
respectively), so their build stages produce the binaries the patches install.
`meshfix` ships a prebuilt module and a builder that rebuilds it in-container
when the binary is absent.

See each directory's `README.md` for detail. Upstream provenance and licensing
are noted there.
