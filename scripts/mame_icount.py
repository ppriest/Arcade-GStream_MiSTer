#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Instructions per frame in MAME, split into work and the idle loop (scripts/mame/icount.lua).

    python scripts/mame_icount.py gstream c000158c-c0001594 [--start 1500] [--frames 10]

The idle range is the PC range of the loop the driver's speedup handler sits in. Prints per frame the
instructions outside that range (work) and inside it (idle), and the most executed PCs of the work.
Writes debug/icount/<set>.txt, and MAME's snapshot of the first traced frame to debug/icount/snap/.
"""
import argparse
import collections
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from mame_capture import NO_WINDOW, check_lua_error, lua_runner_env, mame_cmd, mame_paths   # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    ap.add_argument("idle", help="idle loop PC range, hex lo-hi")
    ap.add_argument("--start", type=int, default=1500)
    ap.add_argument("--frames", type=int, default=10)
    ap.add_argument("--coin", type=int, default=600)
    ap.add_argument("--fire", type=int, default=900)
    ap.add_argument("--keep", action="store_true", help="keep the raw trace")
    a = ap.parse_args()
    lo, hi = (int(x, 16) for x in a.idle.split("-"))
    out = REPO / "debug" / "icount"
    out.mkdir(parents=True, exist_ok=True)
    raw = out / f"{a.set}.tr"
    if raw.exists():
        raw.unlink()
    mame_dir, exe = mame_paths()
    env = dict(os.environ, **lua_runner_env("icount.lua"), CORE_OUT=out.as_posix(), IC_OUT=raw.as_posix(),
               IC_START=str(a.start), IC_FRAMES=str(a.frames), IC_COIN=str(a.coin), IC_FIRE=str(a.fire))
    cmd = mame_cmd(exe, a.set, "icount.lua", mame_dir,
                   ["-nvram_directory", str((out / "nvram").resolve()), "-cfg_directory", str((out / "cfg").resolve()),
                    "-snapshot_directory", str((out / "snap").resolve()), "-nodrc"])
    cmd[cmd.index("-nodebug")] = "-debug"
    subprocess.run(cmd, cwd=str(mame_dir), env=env, capture_output=True, text=True, timeout=7200, **NO_WINDOW)
    check_lua_error(out)
    rows, work, idle = [], 0, 0
    hist = collections.Counter()
    with open(raw, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("I "):
                pc = int(line[2:10], 16)
                if lo <= pc <= hi:
                    idle += 1
                else:
                    work += 1
                    hist[pc & ~0xff] += 1
            elif line.startswith("# frame"):
                rows.append((int(line.split()[2]), work, idle))
                work = idle = 0
    txt = ["# frame, instructions outside the idle range, inside it"]
    txt += [f"{fr} {w} {i}" for fr, w, i in rows]
    txt += ["# work instructions by 256-byte PC block, most executed first"]
    txt += [f"{blk:08x} {n}" for blk, n in hist.most_common(40)]
    (out / f"{a.set}.txt").write_text("\n".join(txt) + "\n", encoding="utf-8")
    print("\n".join(txt[:len(rows) + 1 + 12]))
    if not a.keep:
        raw.unlink()


if __name__ == "__main__":
    main()
