#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Per-frame VRAM, the core against MAME, matched at the frame offset the core's slower boot gives.

    python scripts/vram_compare.py <mame.bin> <rtl.bin>

Both files are 16 KB records, one a frame, the VRAM's 4096 dwords big-endian: MAME's from scripts/mame/vdump.lua
(VD_LO=80000000 VD_HI=80003fff), the core's from sim/sys_tb +vramdump. A record whose contents occur in only one
MAME frame fixes an offset (RTL frame - MAME frame); the dominant offset is reported with the frames that agree
at it, and the first core frame after the first agreement that does not.
"""
import collections
import hashlib
import sys

REC = 0x4000


def frames(path):
    d = open(path, "rb").read()
    return [hashlib.sha1(d[i:i + REC]).digest() for i in range(0, len(d) - REC + 1, REC)]


def main():
    mame, rtl = frames(sys.argv[1]), frames(sys.argv[2])
    where = collections.defaultdict(list)
    for i, h in enumerate(mame):
        where[h].append(i)
    offs = collections.Counter(r - where[h][0] for r, h in enumerate(rtl) if len(where.get(h, [])) == 1)
    if not offs:
        print(f"no core frame matches a unique MAME frame ({len(rtl)} core frames, {len(mame)} MAME frames)")
        return 1
    off, n = offs.most_common(1)[0]
    print(f"{len(rtl)} core frames, {len(mame)} MAME frames; offset {off} (core frame = MAME frame + {off}) fixed by "
          f"{n} unique frames; other offsets: {dict(offs.most_common(4)[1:])}")
    first = next(r for r, h in enumerate(rtl) if 0 <= r - off < len(mame) and mame[r - off] == h)
    agree = sum(1 for r in range(first, len(rtl)) if 0 <= r - off < len(mame) and mame[r - off] == rtl[r])
    span = sum(1 for r in range(first, len(rtl)) if 0 <= r - off < len(mame))
    bad = next((r for r in range(first, len(rtl)) if 0 <= r - off < len(mame) and mame[r - off] != rtl[r]), None)
    print(f"from core frame {first} (MAME frame {first - off}): {agree} of {span} frames identical"
          + (f"; first difference at core frame {bad} (MAME frame {bad - off})" if bad is not None else ""))
    return 0 if agree == span else 1


if __name__ == "__main__":
    sys.exit(main())
