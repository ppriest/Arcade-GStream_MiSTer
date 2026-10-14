#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""MAME's video state and picture at chosen frames (scripts/mame/gscap.lua), for scripts/render_model.py.

    python scripts/gs_capture.py gstream 300,600,1500,2700 [--coin 600] [--fire 900] [--out debug/cap/gstream]

Inputs as scripts/mame_busy.py. Writes f<N>_vram.bin, f<N>_pal.bin, f<N>_scr.txt, f<N>_screen.bin/.txt per frame.
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from mame_capture import NO_WINDOW, check_lua_error, lua_runner_env, mame_cmd, mame_paths   # noqa: E402

# the scroll registers sx0 sy0 sx1 sy1 sx2 sy2 (gstream_32bit_map 278-284, x2222_32bit_map 372-379)
SCROLL = {"gstream": "4f800000,4fa00000,4fc00000,4fe00000,4f000000,4f200000",
          "x2222": "4ff00000,4fe00000,4fd00000,4fc00000,4fb00000,4fa00000"}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    ap.add_argument("frames")
    ap.add_argument("--coin", type=int, default=600)
    ap.add_argument("--fire", type=int, default=900)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    out = (Path(a.out) if a.out else REPO / "debug" / "cap" / a.set).resolve()
    out.mkdir(parents=True, exist_ok=True)
    mame_dir, exe = mame_paths()
    x2 = a.set.startswith("x2222")
    env = dict(os.environ, **lua_runner_env("gscap.lua"), CORE_OUT=out.as_posix(), GC_OUT=out.as_posix(),
               GC_FRAMES=a.frames, GC_COIN=str(a.coin), GC_FIRE=str(a.fire),
               GC_SCROLL=SCROLL["x2222" if x2 else "gstream"], GC_PAL="0" if x2 else "1")
    cmd = mame_cmd(exe, a.set, "gscap.lua", mame_dir,
                   ["-nodrc", "-nvram_directory", str((out / "nv").resolve()), "-cfg_directory", str((out / "cfg").resolve())])
    subprocess.run(cmd, cwd=str(mame_dir), env=env, capture_output=True, timeout=7200, **NO_WINDOW)
    check_lua_error(out)
    got = sorted(int(p.name[1:].split("_")[0]) for p in out.glob("f*_screen.txt"))
    print(f"{a.set}: captured frames {got} in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
