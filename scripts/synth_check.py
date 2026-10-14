#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Standalone Quartus synthesis + fit + timing of the main board (rtl/synth_check/gs_synth: e1_pipe, gs_cpumem,
the backup RAM and the I/O), at the clock in gs_synth.sdc.

    python scripts/synth_check.py [--seed N] [--period NS] [--map-only]

Works in debug/synth/gs_<time> (a copy of rtl/), refuses to run while a JTAG tool holds the marker (hwlock).
Prints the fit summary and the Fmax summary. After Arcade-Vamphalf_MiSTer's scripts/synth_check.py.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
import hwlock  # noqa: E402
from coretools import setting  # noqa: E402

QBIN = Path(setting("QUARTUS_BIN") or "C:/intelFPGA_lite/17.0/quartus/bin64")


def run(tool, args, cwd):
    r = subprocess.run([str(QBIN / (tool + ".exe"))] + args, cwd=cwd, capture_output=True, text=True)
    (cwd / (tool + ".log")).write_text(r.stdout + r.stderr)
    if r.returncode:
        print(r.stdout[-3000:], r.stderr[-2000:])
        sys.exit(f"{tool} failed")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--period", type=float, default=None, help="override the clock period (ns)")
    ap.add_argument("--map-only", action="store_true")
    a = ap.parse_args()
    hwlock.require_no_jtag("synth check")
    sw = REPO / "debug" / "synth"
    sw.mkdir(parents=True, exist_ok=True)
    for old in sw.glob("gs_*"):
        shutil.rmtree(old, ignore_errors=True)
    work = sw / f"gs_{int(time.time())}"
    shutil.copytree(REPO / "rtl", work / "rtl")
    p = work / "rtl" / "synth_check"
    if a.period:
        sdc = p / "gs_synth.sdc"
        sdc.write_text(re.sub(r"-period [0-9.]+", f"-period {a.period}", sdc.read_text()))
    with open(p / "gs_synth.qsf", "a") as q:
        q.write(f"set_global_assignment -name SEED {a.seed}\n")
    run("quartus_map", ["gs_synth", "-c", "gs_synth"], p)
    if a.map_only:
        print((p / "gs_synth.map.summary").read_text())
        return 0
    run("quartus_fit", ["gs_synth", "-c", "gs_synth"], p)
    run("quartus_sta", ["gs_synth", "-c", "gs_synth"], p)
    print((p / "gs_synth.fit.summary").read_text())
    sta = (p / "quartus_sta.log").read_text()
    for m in re.finditer(r"Worst-case setup slack.*|Info.*Slack.*|.*Fmax.*", sta):
        print(m.group(0)[:200])
    return 0


if __name__ == "__main__":
    sys.exit(main())
