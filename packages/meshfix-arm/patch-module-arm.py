#!/usr/bin/env python3
"""Patch the ARM ld -r output so the module owns its init/exit and name.

The vendor wlan_fils.ko template supplies struct module, .modinfo and the
3.14.43 vermagic.  The linker keeps the template's init/exit relocations; rewrite
them to the patcher functions and put "meshpatch" in struct module's name
field (offset 0x0c).
"""

from __future__ import annotations

import struct
import sys

ELF_HDR = 52
SHDR = 40
SYM = 16
REL = 8


def main(src: str, dst: str) -> None:
    data = bytearray(open(src, "rb").read())
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        raise SystemExit(f"{src}: not an ELF32 little-endian file")
    machine = struct.unpack_from("<H", data, 18)[0]
    if machine != 40:
        raise SystemExit(f"{src}: machine {machine}, expected ARM")

    e_shoff = struct.unpack_from("<I", data, 32)[0]
    e_shentsize = struct.unpack_from("<H", data, 46)[0]
    e_shnum = struct.unpack_from("<H", data, 48)[0]
    e_shstrndx = struct.unpack_from("<H", data, 50)[0]
    if e_shentsize != SHDR:
        raise SystemExit(f"{src}: unexpected section header size {e_shentsize}")

    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sections.append(struct.unpack_from("<IIIIIIIIII", data, off))

    shstr = sections[e_shstrndx]
    shstr_data = data[shstr[4]:shstr[4] + shstr[5]]

    def sh_name(sh: tuple[int, ...]) -> str:
        start = sh[0]
        end = shstr_data.find(b"\0", start)
        return shstr_data[start:end].decode()

    symtab = None
    for sh in sections:
        if sh[1] == 2:  # SHT_SYMTAB
            symtab = sh
            break
    if symtab is None:
        raise SystemExit(f"{src}: no symbol table")
    strtab = sections[symtab[6]]
    strings = data[strtab[4]:strtab[4] + strtab[5]]

    symbols: list[str] = []
    for i in range(symtab[5] // SYM):
        off = symtab[4] + i * SYM
        st_name = struct.unpack_from("<I", data, off)[0]
        end = strings.find(b"\0", st_name)
        symbols.append(strings[st_name:end].decode())

    def sym_index(name: str) -> int:
        try:
            return symbols.index(name)
        except ValueError as exc:
            raise SystemExit(f"{src}: symbol {name} not found") from exc

    rel = None
    for sh in sections:
        if sh[1] == 9 and sh_name(sh) == ".rel.gnu.linkonce.this_module":  # SHT_REL
            rel = sh
            break
    if rel is None:
        raise SystemExit(f"{src}: no .rel.gnu.linkonce.this_module")
    target = sections[rel[7]]  # sh_info
    if sh_name(target) != ".gnu.linkonce.this_module":
        raise SystemExit(f"{src}: unexpected relocation target {sh_name(target)}")

    replacements = {
        "init_module": sym_index("meshpatch_init"),
        "cleanup_module": sym_index("meshpatch_cleanup"),
    }
    patched = 0
    for i in range(rel[5] // REL):
        off = rel[4] + i * REL
        r_info = struct.unpack_from("<I", data, off + 4)[0]
        sym = r_info >> 8
        typ = r_info & 0xFF
        old = symbols[sym]
        if old in replacements:
            struct.pack_into("<I", data, off + 4, (replacements[old] << 8) | typ)
            patched += 1
    if patched != 2:
        raise SystemExit(f"{src}: patched {patched} relocations, expected 2")

    name_off = target[4] + 0x0C
    data[name_off:name_off + 64] = b"meshpatch\0" + b"\0" * 54

    with open(dst, "wb") as fh:
        fh.write(data)
    print(f"patched {dst}: name=meshpatch, {patched} relocations")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} IN.ko OUT.ko")
    main(sys.argv[1], sys.argv[2])
