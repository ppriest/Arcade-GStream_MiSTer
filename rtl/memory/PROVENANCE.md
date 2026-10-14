# rtl/memory provenance

Copied unchanged from `Arcade-Vamphalf_MiSTer/rtl/memory/` (commits in `scripts/vendor.json`). Vamphalf's
`rtl/memory/PROVENANCE.md` has the chain and local changes of each:

| File | Origin |
|---|---|
| `sdram.sv` | Sorgelig's `sdram.v` (GPL-3.0-or-later), burst 4 (Psikyo), 26-bit (Fuuki), double read (KonamiGX, then all three ports in Vamphalf), burst writes and `RFS_INTERVAL` (Vamphalf) |
| `sdram_upstream_reference.sv` | the unmodified upstream, for diffing |
| `sdram_download.sv` | Arcade-KonamiGX_MiSTer |
| `ddram_phy.sv` | Arcade-Seta_MiSTer, from Fuuki via Psikyo |
| `vh_rom_loader.sv` | Vamphalf, after Seta's `rom_loader.sv`: the DDR3 image copied to SDRAM at load time |
| `vh_dpram.sv` | Vamphalf: a dual-port RAM as an explicit `altsyncram` |

`../vh_cache.sv` (the E1's direct-mapped cache) is Vamphalf's, unchanged.
