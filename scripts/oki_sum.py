#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The sample-ROM checksums gs_sound's check computes (chk_start, chk_seg), from the download image.

    python scripts/oki_sum.py [debug/sys/gstream.bin]

One line per segment: 256 KB of OKI1 (0-3) or OKI2 (4-7). Per 8-byte granule, sum = rotl(sum, 1) ^ dword 0 ^
dword 1 rotated by 16, the dwords little-endian, as SDRAM returns them (sdram.sv: byte k of a granule in bits
8k+7..8k). Compare with probe S's chk_sum after `python scripts/read_issp.py S pulse ...`.
"""
import re
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def sdram_map():
    t = (REPO / "rtl" / "gs_sdram_map.svh").read_text()
    return {m[0]: int(m[1], 16) for m in re.findall(r"localparam \[26:0\] (\w+)\s*=\s*27'h([0-9a-fA-F]+)", t)}


def seg_sum(img, base):
    s = 0
    for lo, hi in struct.iter_unpack("<II", img[base:base + 0x40000]):
        s = ((s << 1) | (s >> 31)) & 0xffffffff
        s ^= lo ^ (((hi << 16) | (hi >> 16)) & 0xffffffff)
    return s


def main():
    img = Path(sys.argv[1] if len(sys.argv) > 1 else REPO / "debug" / "sys" / "gstream.bin").read_bytes()
    sm = sdram_map()
    for seg in range(8):
        base = (sm["SD_OKI2"] if seg & 4 else sm["SD_OKI1"]) + (seg & 3) * 0x40000
        print(f"segment {seg} (0x{base:07x}): 0x{seg_sum(img, base):08X}")


if __name__ == "__main__":
    main()
