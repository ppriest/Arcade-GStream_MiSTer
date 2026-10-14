#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The renderer RTL (sim/video_tb) against render_model.py, frame by frame.

    python scripts/video_check.py gstream [--cap debug/cap/gstream] [--lat 30] [--busy 0] [frames ...]

For every captured frame (scripts/gs_capture.py), or those named: runs the bench on the capture and compares its
320 x 240 frame with the model's, pixel by pixel (the model is itself checked against MAME by render_model.py).
Prints each frame's differing pixels, the bench's overrun count and longest line pass.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
import render_model as rm                                   # noqa: E402
from e1_regress import bash                                 # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    ap.add_argument("frames", nargs="*", type=int)
    ap.add_argument("--cap", default=None)
    ap.add_argument("--img", default=None)
    ap.add_argument("--lat", type=int, default=30)
    ap.add_argument("--busy", type=int, default=0)
    ap.add_argument("--flip", action="store_true", help="flip on: the model's frame turned 180 degrees")
    a = ap.parse_args()
    cap = Path(a.cap) if a.cap else REPO / "debug" / "cap" / a.set
    img = Path(a.img) if a.img else REPO / "debug" / "sys" / f"{a.set}.bin"
    gfx = rm.load_gfx(img.read_bytes(), rm.sdram_map())
    frames = a.frames or sorted(int(p.name[1:].split("_")[0]) for p in cap.glob("f*_screen.txt"))
    bad = 0
    for f in frames:
        base = cap / f"f{f}"
        out = cap / f"f{f}_rtl.ppm"
        r = subprocess.run([bash(), "scripts/run_verilator.sh", "video_tb", f"+img={img.as_posix()}",
                            f"+cap={base.as_posix()}", f"+out={out.as_posix()}", f"+lat={a.lat}", f"+busy={a.busy}", f"+flip={int(a.flip)}"],
                           cwd=REPO, capture_output=True, text=True)
        stats = re.search(r"overrun lines (\d+), longest pass (\d+)", r.stdout)
        if r.returncode or not out.exists() or not stats:
            print(f"frame {f}: bench failed\n{r.stdout[-1500:]}{r.stderr[-1500:]}")
            bad += 1
            continue
        scroll = [int(x, 16) for x in Path(f"{base}_scr.txt").read_text().split()]
        pens = rm.render(Path(f"{base}_vram.bin").read_bytes(), None, scroll, gfx, rm.XOFF[a.set])
        pal = rm.palette_rgb(Path(f"{base}_pal.bin").read_bytes())
        model = np.zeros((rm.H, rm.W, 3), np.uint8)
        m = pens >= 0
        model[m] = pal[pens[m]]
        if a.flip:
            model = model[::-1, ::-1]
        raw = out.read_bytes()
        rtl = np.frombuffer(raw[raw.index(b"255\n") + 4:], np.uint8).reshape(rm.H, rm.W, 3)
        diff = np.any(rtl != model, 2)
        n = int(diff.sum())
        bad += n != 0 or stats.group(1) != "0"
        first = f" (first at x {np.argwhere(diff)[0][1]}, y {np.argwhere(diff)[0][0]})" if n else ""
        print(f"frame {f}: {n} pixels differ{first}; overrun lines {stats.group(1)}, longest pass {stats.group(2)} of 3888")
    print(f"{len(frames) - bad} of {len(frames)} frames identical to the model with no overrun")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
