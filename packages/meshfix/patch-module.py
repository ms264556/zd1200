#!/usr/bin/env python3
"""Patch the ld -r output so the module owns its init/exit and name.

The wlan_fils.c stub supplies struct module, .modinfo and the vermagic.  The
linker keeps the stub's init/exit relocations; rewrite them to the patcher
functions and put "meshpatch" in struct module's name field (offset 0x0c).
"""

import struct
import sys

path = sys.argv[1]
data = bytearray(open(path, "rb").read())

if data[:6] != b"\x7fELF\x01\x02":
    sys.exit(f"{path}: not an ELF32 big-endian object")

e_shoff = struct.unpack_from(">I", data, 0x20)[0]
e_shentsize = struct.unpack_from(">H", data, 0x2E)[0]
e_shnum = struct.unpack_from(">H", data, 0x30)[0]
e_shstrndx = struct.unpack_from(">H", data, 0x32)[0]


def section(index):
    return struct.unpack_from(">IIIIIIIIII", data, e_shoff + index * e_shentsize)


def section_name(index):
    start = section(e_shstrndx)[4] + section(index)[0]
    return bytes(data[start:]).split(b"\0", 1)[0].decode()


sections = {section_name(i): i for i in range(e_shnum)}
symtab = section(sections[".symtab"])
strtab = section(symtab[6])
symbols = {}
for index in range(symtab[5] // 16):
    st_name = struct.unpack_from(">I", data, symtab[4] + index * 16)[0]
    name = bytes(data[strtab[4] + st_name:]).split(b"\0", 1)[0].decode()
    symbols[name] = index

init_sym = symbols["meshpatch_init"]
cleanup_sym = symbols["meshpatch_cleanup"]

rel = section(sections[".rel.gnu.linkonce.this_module"])
for offset in range(rel[4], rel[4] + rel[5], 8):
    r_info = struct.unpack_from(">I", data, offset + 4)[0]
    old_sym = r_info >> 8
    new_sym = None
    name = next((n for n, i in symbols.items() if i == old_sym), "")
    if "init" in name:
        new_sym = init_sym
    elif "cleanup" in name or "exit" in name:
        new_sym = cleanup_sym
    if new_sym is not None:
        struct.pack_into(">I", data, offset + 4, (new_sym << 8) | (r_info & 0xFF))

this_module = section(sections[".gnu.linkonce.this_module"])
# struct module: state (4) + list (8), then name at 0x0c.
data[this_module[4] + 0x0C:this_module[4] + 0x0C + 64] = b"meshpatch\0" + b"\0" * 54

open(path, "wb").write(data)
