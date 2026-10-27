# Third-party code and licences

**This project is GPL-3.0-or-later.** `LICENSE` carries the GPLv3 text. jotego's JT6295 and the SDRAM controller
are GPL-3.0-or-later, so the whole is GPL-3; code can come in from GPL-2-or-later MiSTer cores, not go back out
(Arcade-KonamiGX_MiSTer's `THIRD-PARTY.md`, "Why GPL-3, and why it is one-way").

Each vendored directory's `PROVENANCE.md` names the source and every local change; `scripts/vendor.json` pins each
copied file to its source commit and `python scripts/vendor_sync.py` checks it. This file records what each dependency
obliges.

## Dependencies

### Arcade-Vamphalf_MiSTer — GPL-3.0-or-later

The Hyperstone E1 CPU (`rtl/e1/`, written there from MAME's interpreter, BSD-3-Clause), its cache (`rtl/vh_cache.sv`)
and memory unit (`rtl/gs_cpumem.sv` is generated from its `vh_cpumem.sv` by `scripts/gen_gs_cpumem.py`), the memory
modules (`rtl/memory/`: the ROM loader, `ddram_phy`, `vh_dpram`; their own chains in `rtl/memory/PROVENANCE.md`), the
debug probes (`rtl/debug/`), the CRT Adjust glue (`rtl/video/gs_crt.sv`, adapted from `vh_crt.sv`), the PLL wrapper,
the E1 benches and MAME trace tools (`sim/e1_tb`, `scripts/e1_*.py`, `scripts/mame_e1_trace.py`). Same authors and
licence as this project. Obligations: publish the source.

### jotego/jt6295 — GPL-3.0-or-later

<https://github.com/jotego/jt6295> at `7d76b0be8cd8f85f3ae741178c9830b20e2071a1`, via Arcade-Fuuki_MiSTer and
Vamphalf: `rtl/sound/jt6295/`, unmodified. `oki_rom_bridge.sv` and `sample_cache.sv` (Fuuki's, after Psikyo's) feed its
ROM bus. Obligations: publish the source.

### Sorgelig's SDRAM controller — GPL-3.0-or-later

`rtl/memory/sdram.sv`: Sorgelig's `sdram.v`, extended in Psikyo, Fuuki, KonamiGX and Vamphalf (burst 4, double reads,
burst writes); `sdram_upstream_reference.sv` is the unmodified upstream for diffing. Obligations: publish the source,
keep the change notices in its header.

### rmonic79's CRT Adjust — GPL-3.0-or-later

`rtl/video/crt_adjust.sv`, unmodified (via Vamphalf). Obligations: publish the source.

### Sorgelig's screen rotation — GPL-2.0-or-later

`rtl/video/screen_rotate_two.sv`, unmodified (via Vamphalf). GPL-2.0-or-later into a GPL-3.0-or-later work is direct.

### MiSTer-devel/Template_MiSTer — GPL-2.0-or-later (`sys/`)

The framework, unmodified, pinned at `9c8eadb` (2026-10-10). Its grant is "or later", which is what lets it
combine with GPL-3 code. The two upstream commits after the pin (`afd7808`, `5dda373`, 2026-10-16) are not
taken yet: the released `.rbf` was built against the pinned tree.

## Reference material, not code

MAME (<https://github.com/mamedev/mame>, `src/mame/promat/gstream.cpp` and the devices it uses, BSD-3-Clause and
GPL-2.0-or-later per file) is the reference for the hardware's behaviour; no MAME source is compiled into the core.
The E1 RTL was written from MAME's `e132xs` interpreter (BSD-3-Clause) in Vamphalf, and says so in its header.

## Release checklist

- every `PROVENANCE.md` current, `python scripts/vendor_sync.py` reports no error
- an SPDX header on every file of ours
- `sys/` unmodified against Template_MiSTer
- `LICENSE` is the GPLv3 text
