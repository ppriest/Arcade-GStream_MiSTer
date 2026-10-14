# rtl/e1 provenance

Copied unchanged from `Arcade-Vamphalf_MiSTer/rtl/e1/` (GPL-3.0); the commit of each file is in
`scripts/vendor.json`, and `python scripts/vendor_sync.py` reports a local edit (an error) or upstream movement. A
change to the CPU is made in Vamphalf and copied here with `vendor_sync.py --update`, then the conformance suite is
rerun (`python scripts/e1_regress.py --replay --pipe --waits 0 3` on Vamphalf's traces copied to `debug/e1`).

Origin: written in Vamphalf from MAME's E1 interpreter (`src/devices/cpu/e132xs/e132xs.cpp`, `e132xsop.hxx`,
`e1defs.h`; BSD-3-Clause, copyright-holders Pierpaolo Prazzoli and the MAME team). Its verification is in
Vamphalf's `docs/ROADMAP.md`; this core's is in `docs/ROADMAP.md`, Phase 0. The build uses `e1_pipe.sv` and
`e1_regram.sv`; `e1_cpu.sv` is the benches' reference and fallback.
