#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Sprite and tilemap census from per-frame VRAM dumps in MAME (scripts/mame/vdump.lua), gstream.

    python scripts/vram_census.py gstream [--skip 600] [--frames 1800] [--coin 600] [--tag _play]
    python scripts/vram_census.py gstream --reuse --tag _play      # re-read debug/census/<set><tag>.bin

Follows gstream.cpp screen_update (750-811): sprites 0..831 (the clk budget, 779-785), each drawn at
(x - 2, y), (x - 2, y - 256), (x - 514, y), (x - 514, y - 256) on a 320 x 240 screen; m_xoffset = 2
(init_gstream, 1094). Per visible line: sprite placements crossing it, and those whose 16-pixel row
there has a non-zero pixel (the gfx1 ROM, from the set's zip). Writes debug/census/<set><tag>.txt.
"""
import argparse
import collections
import os
import subprocess
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from mame_capture import (NO_WINDOW, check_lua_error, load_env, lua_env, lua_runner_env,  # noqa: E402
                          mame_cmd, mame_paths, regions)

W, H, XOFF, NSPR = 320, 240, 2, 832
GFX1 = [("gs_gr_07.u107", "gs_gr_11.u108"), ("gs_gr_08.u109", "gs_gr_12.u110"),
        ("gs_gr_09.u180", "gs_gr_13.u181"), ("gs_gr_10.u182", "gs_gr_14.u183")]


def find_zip(name):
    mame_dir, _ = mame_paths()
    extra = os.environ.get("MAME_ROMPATH", load_env().get("MAME_ROMPATH", ""))
    for d in [REPO / "roms", mame_dir / "roms", *[Path(p) for p in extra.split(";") if p]]:
        if (d / f"{name}.zip").exists():
            return d / f"{name}.zip"
    sys.exit(f"{name}.zip not found")


def sprite_rows(zpath):
    """Non-empty flags per (tile, row): ROM_LOAD32_WORD pairs, gstream.cpp 898-906."""
    z = zipfile.ZipFile(zpath)
    gfx = bytearray(0x1000000)
    for i, (a, b) in enumerate(GFX1):
        ra, rb = z.read(a), z.read(b)
        base = i * 0x400000
        gfx[base + 0:base + 0x400000:4] = ra[0::2]
        gfx[base + 1:base + 0x400000:4] = ra[1::2]
        gfx[base + 2:base + 0x400000:4] = rb[0::2]
        gfx[base + 3:base + 0x400000:4] = rb[1::2]
    zero = bytes(16)
    return bytearray(gfx[k:k + 16] != zero for k in range(0, len(gfx), 16))


def dump(game, out, skip, frames, coin):
    r = regions(game)
    mame_dir, exe = mame_paths()
    inp = r.get("inputs", {})
    env = dict(os.environ, **lua_env(r), **lua_runner_env("vdump.lua"), CORE_OUT=out.parent.as_posix(),
               VD_OUT=out.as_posix(), VD_LO="80000000", VD_HI="80003fff", VD_SKIP=str(skip),
               VD_FRAMES=str(frames), VD_COIN=str(coin), VD_COIN_PERIOD=str(inp.get("coin_period", 0)),
               VD_START_PERIOD=str(inp.get("start_period", 0)), VD_PRESS=str(inp.get("press_len", 6)))
    cmd = mame_cmd(exe, game, "vdump.lua", mame_dir,
                   ["-nodrc", "-snapshot_directory", (out.parent / "snap").as_posix()])
    subprocess.run(cmd, cwd=str(mame_dir), env=env, capture_output=True, timeout=7200, **NO_WINDOW)
    check_lua_error(out.parent)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    ap.add_argument("--skip", type=int, default=600)
    ap.add_argument("--frames", type=int, default=1800)
    ap.add_argument("--coin", type=int, default=0)
    ap.add_argument("--tag", default="")
    ap.add_argument("--reuse", action="store_true")
    a = ap.parse_args()
    outdir = REPO / "debug" / "census"
    outdir.mkdir(parents=True, exist_ok=True)
    raw = outdir / f"{a.set}{a.tag}.bin"
    if not a.reuse:
        dump(a.set, raw, a.skip, a.frames, a.coin)
    rows = sprite_rows(find_zip(a.set))
    data = raw.read_bytes()
    rec = 0x4000
    nfr = len(data) // rec
    per_line_all, per_line_vis = [], []      # per frame: max over lines
    frame_vis = []                           # per frame: placements with any visible non-empty row
    cols, tile_pal, tile_hi = collections.Counter(), collections.Counter(), collections.Counter()
    line_hist = collections.Counter()
    for fr in range(nfr):
        v = data[fr * rec:(fr + 1) * rec]
        d = [int.from_bytes(v[k:k + 4], "big") for k in range(0, rec, 4)]
        la, lv = [0] * H, [0] * H
        nvis = 0
        for i in range(0, NSPR * 4, 4):
            code, x, y, col = d[i] & 0xffff, d[i + 1] & 0x1ff, d[i + 2] & 0xff, d[i + 3] & 0x1f
            any_vis = False
            for dx in (0, 512):
                sx = x - XOFF - dx
                if sx > W - 1 or sx + 15 < 0:
                    continue
                for dy in (0, 256):
                    sy = y - dy
                    for r in range(16):
                        ln = sy + r
                        if 0 <= ln < H:
                            la[ln] += 1
                            if rows[code * 16 + r]:
                                lv[ln] += 1
                                any_vis = True
            if any_vis:
                nvis += 1
                cols[col] += 1
        per_line_all.append(max(la))
        per_line_vis.append(max(lv))
        frame_vis.append(nvis)
        for c in lv:
            line_hist[c] += 1
        for layer in range(3):
            for t in range(256):
                e = d[layer * 0x100 + t] >> 16
                tile_pal[(layer, e >> 14)] += 1
                if e & 0x3000:
                    tile_hi[layer] += 1

    def pct(xs, q):
        s = sorted(xs)
        return s[min(len(s) - 1, int(q * len(s)))]

    lines = [f"{a.set}{a.tag}: {nfr} frames",
             "sprite placements crossing a visible line, max per frame: median {} 99% {} max {}".format(
                 pct(per_line_all, .5), pct(per_line_all, .99), max(per_line_all)),
             "  with a non-empty row on that line:                    median {} 99% {} max {}".format(
                 pct(per_line_vis, .5), pct(per_line_vis, .99), max(per_line_vis)),
             "sprites with a visible non-empty row, per frame: median {} 99% {} max {}".format(
                 pct(frame_vis, .5), pct(frame_vis, .99), max(frame_vis)),
             "visible lines by non-empty sprite rows on them (count: lines): " +
             ", ".join(f"{k}:{line_hist[k]}" for k in sorted(line_hist)),
             "colour codes of visible sprites: " + ", ".join(f"{k}:{cols[k]}" for k in sorted(cols)),
             "tile palette select (layer, bits 15:14): " + ", ".join(f"{k}:{tile_pal[k]}" for k in sorted(tile_pal)),
             "tile entries with bits 13:12 set, per layer: " + ", ".join(f"{k}:{tile_hi[k]}" for k in sorted(tile_hi))]
    (outdir / f"{a.set}{a.tag}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
