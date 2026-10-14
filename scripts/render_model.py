#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""gstream.cpp's screen_update (750-811) in Python: a frame from captured VRAM, palette and scroll registers.

    python scripts/render_model.py gstream [--cap debug/cap/gstream] [--img debug/sys/gstream.bin] [--png]

For every frame captured by scripts/gs_capture.py, renders the frame and compares it with MAME's picture
(f<N>_screen.bin); --png writes f<N>_model.png and, where they differ, f<N>_diff.png. The graphics come from the
download image (scripts/build_mra.py --image), at rtl/gs_sdram_map.svh's offsets: the bytes MAME's regions hold.

The model, line by line with the driver:
  black (bitmap.fill(0), 772); tilemaps 2, 1, 0 (775-777, draw_bg 721-748); sprites 0..831 (779-809)
  tilemap n: 16 x 13 tiles of 32 x 32 from (scrollx >> 5, scrolly >> 5), each at (x*32 - (scrollx & 31) - xoff,
             y*32 - (scrolly & 31)); entry = VRAM dword (n * 0x100 + (tx & 15) + (ty & 15) * 16) >> 16; code bits
             11:0, colour bits 15:14; pen 0 transparent; colour 0x1000 + 0x400 * n + colour * 256 + pen
  sprite i: code, x (9 bits), y (8 bits), colour (5 bits) from the low halves of dwords 4i..4i+3; drawn at
             (x - xoff, y), (x - xoff, y - 256), (x - xoff - 512, y), (x - xoff - 512, y - 256); pen 0 transparent;
             colour * 256 + pen
  palette:   entry e is the BGR565 halfword e of the palette RAM (the even one in a dword's bits 31:16)
"""
import argparse
import re
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
W, H = 320, 240
XOFF = {"gstream": 2}


def sdram_map():
    text = (REPO / "rtl" / "gs_sdram_map.svh").read_text(encoding="utf-8")
    return {k: int(v, 16) for k, v in re.findall(r"localparam \[26:0\] (SD_\w+)\s*=\s*27'h([0-9a-fA-F]+);", text)}


def palette_rgb(pal_bytes):
    """BGR_565 (emupal.cpp 315): R bits 4:0, G 10:5, B 15:11, widened by bit replication."""
    v = np.frombuffer(pal_bytes, dtype=">u2").astype(np.uint32)
    r, g, b = v & 0x1f, (v >> 5) & 0x3f, (v >> 11) & 0x1f
    r8, g8, b8 = (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)
    rgb = np.zeros((0x4000, 3), np.uint8)              # past the RAM's 0x3800 entries: black, never used
    rgb[:len(v)] = np.stack([r8, g8, b8], 1)
    return rgb


def render(vram, pal, scroll, gfx, xoff):
    """Pen index per pixel (-1 = the black fill), as MAME's draw order leaves it."""
    d = np.frombuffer(vram, dtype=">u4").astype(np.uint32)
    out = np.full((H, W), -1, np.int32)
    spr, tiles = gfx
    for n in (2, 1, 0):
        sx, sy = scroll[2 * n] & 0x1ff, scroll[2 * n + 1] & 0x1ff
        ram = d[n * 0x100:n * 0x100 + 0x100]
        tset = tiles[n]
        basey = sy >> 5
        for ty in range(13):
            basex = sx >> 5
            for tx in range(16):
                e = int(ram[(basex & 15) + (basey & 15) * 16]) >> 16
                code, col = e & 0x0fff, (e >> 14) & 3
                px, py = tx * 32 - (sx & 31) - xoff, ty * 32 - (sy & 31)
                blit(out, tset[code], px, py, 0x1000 + 0x400 * n + col * 256)
                basex += 1
            basey += 1
    for i in range(832):
        code, x, y, col = (int(d[4 * i + k]) & m for k, m in enumerate((0xffff, 0x1ff, 0xff, 0x1f)))
        for dx, dy in ((0, 0), (0, 256), (512, 0), (512, 256)):
            blit(out, spr[code], x - xoff - dx, y - dy, col * 256)
    return out


def blit(out, tile, px, py, base):
    h, w = tile.shape
    x0, y0, x1, y1 = max(px, 0), max(py, 0), min(px + w, W), min(py + h, H)
    if x0 >= x1 or y0 >= y1:
        return
    t = tile[y0 - py:y1 - py, x0 - px:x1 - px]
    region = out[y0:y1, x0:x1]
    mask = t != 0
    region[mask] = base + t[mask]


def load_gfx(img, sm):
    raw = np.frombuffer(img, np.uint8)
    spr = raw[sm["SD_SPR"]:sm["SD_SPR"] + 0x1000000].reshape(65536, 16, 16).astype(np.int32)
    tiles = [raw[b:b + 0x400000].reshape(4096, 32, 32).astype(np.int32)
             for b in (sm["SD_TILE0"], sm["SD_TILE1"], sm["SD_TILE2"])]
    return spr, tiles


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    ap.add_argument("--cap", default=None)
    ap.add_argument("--img", default=None)
    ap.add_argument("--png", action="store_true")
    a = ap.parse_args()
    cap = Path(a.cap) if a.cap else REPO / "debug" / "cap" / a.set
    img = Path(a.img) if a.img else REPO / "debug" / "sys" / f"{a.set}.bin"
    gfx = load_gfx(img.read_bytes(), sdram_map())
    frames = sorted(int(p.name[1:].split("_")[0]) for p in cap.glob("f*_screen.txt"))
    bad = 0
    for f in frames:
        base = cap / f"f{f}"
        scroll = [int(x, 16) for x in Path(f"{base}_scr.txt").read_text().split()]
        pens = render(Path(f"{base}_vram.bin").read_bytes(), None, scroll, gfx, XOFF[a.set])
        rgb_pal = palette_rgb(Path(f"{base}_pal.bin").read_bytes())
        model = np.zeros((H, W, 3), np.uint8)
        m = pens >= 0
        model[m] = rgb_pal[pens[m]]
        w, h = (int(x) for x in Path(f"{base}_screen.txt").read_text().split())
        scr = np.frombuffer(Path(f"{base}_screen.bin").read_bytes(), "<u4").reshape(h, w)
        mame = np.stack([(scr >> 16) & 255, (scr >> 8) & 255, scr & 255], 2).astype(np.uint8)
        diff = np.any(model != mame, 2)
        n = int(diff.sum())
        bad += n != 0
        print(f"frame {f}: {n} of {W * H} pixels differ" + (f" (first at x {np.argwhere(diff)[0][1]}, y {np.argwhere(diff)[0][0]})" if n else ""))
        if a.png:
            from PIL import Image
            Image.fromarray(model).save(f"{base}_model.png")
            if n:
                d = np.zeros((H, W, 3), np.uint8)
                d[diff] = (255, 0, 0)
                Image.fromarray(d).save(f"{base}_diff.png")
    print(f"{len(frames) - bad} of {len(frames)} frames pixel-identical to MAME")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
