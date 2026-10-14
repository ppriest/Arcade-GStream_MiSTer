#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The whole board's frames (sim/sys_tb +snap) against render_model.py on the state they were drawn from.

    python scripts/sys_video_check.py <dir> [--img debug/sys/gstream.bin]

For every f<N>_rtl.ppm in <dir>, renders f<N>_vram.bin, _pal.bin and _scr.txt (the bench's VRAM, palette and scroll
registers at that frame's vblank interrupt, which the CPU does not change during the frame shown before it) with the
model and compares pixel by pixel. The model equals MAME (render_model.py), and the board's VRAM equals MAME's at the
boot offset (scripts/vram_compare.py), so this closes the loop under the CPU's own timing.
"""
import argparse
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
import render_model as rm                                   # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dir")
    ap.add_argument("--img", default=str(REPO / "debug" / "sys" / "gstream.bin"))
    a = ap.parse_args()
    d = Path(a.dir)
    gfx = rm.load_gfx(Path(a.img).read_bytes(), rm.sdram_map())
    frames = sorted(int(p.name[1:].split("_")[0]) for p in d.glob("f*_rtl.ppm"))
    bad = 0
    for f in frames:
        base = d / f"f{f}"
        scroll = [int(x, 16) for x in Path(f"{base}_scr.txt").read_text().split()]
        pens = rm.render(Path(f"{base}_vram.bin").read_bytes(), None, scroll, gfx, 2)
        pal = rm.palette_rgb(Path(f"{base}_pal.bin").read_bytes())
        model = np.zeros((rm.H, rm.W, 3), np.uint8)
        m = pens >= 0
        model[m] = pal[pens[m]]
        raw = Path(f"{base}_rtl.ppm").read_bytes()
        rtl = np.frombuffer(raw[raw.index(b"255\n") + 4:], np.uint8).reshape(rm.H, rm.W, 3)
        diff = np.any(rtl != model, 2)
        n = int(diff.sum())
        bad += n != 0
        first = f" (first at x {np.argwhere(diff)[0][1]}, y {np.argwhere(diff)[0][0]})" if n else ""
        print(f"frame {f}: {n} pixels differ{first}")
    print(f"{len(frames) - bad} of {len(frames)} frames identical to the model")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
