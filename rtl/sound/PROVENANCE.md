# rtl/sound provenance

Copied unchanged from `Arcade-Vamphalf_MiSTer/rtl/sound/` (commits in `scripts/vendor.json`). GPL-3.0-or-later.

| Path | Origin |
|---|---|
| `jt6295/hdl/jt6295*.v`, `jt6295/LICENSE` | jotego's JT6295, github.com/jotego/jt6295 `master` at `7d76b0be8cd8f85f3ae741178c9830b20e2071a1`, via Arcade-Fuuki_MiSTer `11df2b8` and Vamphalf; without `jt12_comb.v`, `jt12_interpol.v` and the FIR tables (`INTERPOL = 0` leaves them unused) |
| `oki_rom_bridge.sv`, `sample_cache.sv` | Arcade-Fuuki_MiSTer at the same commit, via Vamphalf: jt6295's ROM bus as held req/valid fetches, served from a 64-bit granule per channel with next-granule prefetch |
