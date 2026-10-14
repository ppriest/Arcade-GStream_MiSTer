# G-Stream / X2222 — MiSTer Core Roadmap

**Approved by the user. A phase whose scope changes goes back for approval.**

## Context

Goal: a DE10-nano MiSTer core for the Oriental Soft Hyperstone board of MAME's `promat/gstream.cpp` (G-Stream G2020,
X2222 and its prototype), a Quartus 17.0.2 project producing one `.rbf` and a `.mra` per set, reusing proven open
components where they exist.

The CPU is not new work: the board's E1-32XT is MAME's `E132X`, the device Arcade-Vamphalf_MiSTer's `e1_pipe` already
runs for Age Of Heroes (`aoh`, 1,000,000 instructions equal to MAME's trace, plays on the board). The sound is two
M6295s, for which `jt6295` is vendored in Vamphalf. What is new:

1. **The video**: three 512 x 512 tilemaps of 32 x 32 8 bpp tiles and a list of 832 16 x 16 8 bpp sprites, from MAME's
   `screen_update`; X2222's 16-bit direct-colour variant of both.
2. **The memory unit for this map**, generated from Vamphalf's `vh_cpumem.sv` as Arcade-Eolith_MiSTer generates its own.
3. **CPU throughput**: G-Stream's CPU does three times the work per frame of `aoh`, the heaviest set the E1 core runs
   now. Whether the core keeps up at the board's frame rate is the Phase 0 gate (HARDWARE_NOTES, Feasibility).

Cross-cutting findings from the previous cores are in **[`LESSONS_LEARNED.md`](LESSONS_LEARNED.md)**.
Working practice built on them is in **[`WORKFLOW.md`](WORKFLOW.md)**. The entries that already
bind decisions here are collected under "Pitfalls that already bind decisions here".

## Progress

**Phase 0 passed; Phase 1 under way.** Criterion 3's bar is no frame lost after boot (the user's decision at the gate:
at 60.75 MHz 13 frames of 2,773 exceed 0.9 of the frame, none is lost).

Phase 1: `scripts/render_model.py` (gstream.cpp `screen_update` transcribed) renders MAME's captured VRAM, palette and
scroll registers pixel-identically to MAME's picture on 9 of 9 frames: attract 200, 400, 550 and play 1500, 1800,
2100, 2400, 2700, 2750 (`scripts/gs_capture.py`, inputs as `scripts/mame_busy.py`; `docs/LESSONS_LEARNED.md` has the
one-frame pairing the capture needed), and on 179 of 179 frames sampled every 10 from 1510 to 3290.
`rtl/video/gs_video.sv` (the renderer: tiles from DDR3 into map-column line buffers, the 832-entry sprite scan with the
empty-tile table, sprites a pixel a clock, the mixer) against the model in `sim/video_tb` (`scripts/video_check.py`, a
DDR3 model returning bursts in order): 9 of 9 frames identical, no line overrun, longest pass 1,463 of 3,888 clocks at 30
clocks of DDR3 latency, 1,669 at 80 clocks with the port busy 40% of clocks; the six heaviest sampled frames (up to 73
non-empty sprites on a line, frames 2560-2790) identical at 80/40, longest pass 2,145. **Phase 1's exit met in
simulation.** Flip screen is Phase 2's (`video_audio_options.md`). [`HARDWARE_NOTES.md`](HARDWARE_NOTES.md) has the board from the driver and the MAME
measurements (`caba259`): CPU busy time, instructions per frame in play, the video-write sweep and the sprite census.

Phase 0, criterion 1: the E1, memory, sound, debug and bench files are copied from Vamphalf `ed0c8a3` (each pinned to
its last-change commit in `scripts/vendor.json`; `vendor_sync.py`: 48 files, 0 edited). The conformance suite replayed
on the copied `e1_pipe` (`python scripts/e1_regress.py --replay --pipe --waits 0 3`, Vamphalf's traces in `debug/e1`):
104 of 104 runs pass, every line identical to Vamphalf's own run including clocks per instruction; 255 of 255 primary
opcodes executed. `jt6295` and `sdram.sv` came without benches of their own; the whole-board bench (criterion 2) is
their first check here.

Phase 0, criterion 2 (`2e9942e`): `rtl/gs_cpumem.sv` (generated from Vamphalf's `vh_cpumem.sv` by
`scripts/gen_gs_cpumem.py`), `rtl/gs_main.sv`, `rtl/sound/gs_sound.sv`, `rtl/video/gs_video.sv` (RAMs and raster only)
and `sim/sys_tb` on the real SDRAM controller. Against MAME's 1,000,000-instruction trace from reset
(`sim/ref/gstream`): PCs agree for 785,785 instructions, where the core takes its first vblank interrupt (it reaches
that point in its third frame, MAME before its first vblank); all 348,922 data accesses before it agree. Over a long run,
attract mode with no inputs, the VRAM at every frame's end equals MAME's for 2,331 of 2,331 frames at an offset of 69
frames, the core's slower boot (`scripts/vram_compare.py`, MAME's dump from `scripts/mame/vdump.lua`). The sound chips'
status reads are inside that run.

Phase 0, criterion 4 (`9e19383`): the main board alone (`scripts/synth_check.py`, `rtl/synth_check/gs_synth`) at 54 MHz:
15,337 ALMs, 4,222 registers, 43 RAM blocks, 7 DSP blocks, worst setup slack +2.755 ns (slow 85C, seed 1).

Phase 0, criterion 3, in progress (`sim/sys_tb +idle=c000158c:c0001594`, inputs as `scripts/mame_busy.py`, 1,800
frames; busy = the frame's share before the CPU's last return to the idle loop; frames 1-144 are boot):

| `clk_sys` 54 MHz unless marked; port-0 load (16-byte reads a visible line) | busy median | 90% | 99% | max | frames lost after boot | clk/instr |
|---|---|---|---|---|---|---|
| none (MAME: 0.209 / 0.256 / 0.286 / 0.586 of a 64 MHz frame) | 0.621 | 0.746 | 0.841 | 0.905 | 0 | 2.44 |
| 140 on every line (the census's worst line, everywhere) | 0.778 | 0.983 | 0.988 | 0.990 | 365, every third frame from 878 | 3.31 |
| 72 on every line (the census's average) | 0.821 | 0.941 | 0.983 | 0.998 | 110 | 3.13 |
| 86 on every line (99% of lines carry fewer) | 0.796 | 0.934 | 0.992 | 0.999 | 260 | 3.10 |
| none, to frame 2,900 (the heavy stretch around 2,550-2,800 included) | 0.684 | 0.849 | 0.982 | 1.000 | 36, in 2,553-2,796 | 2.57 |
| **60.75 MHz**, none (graphics from DDR3), to frame 2,900 | **0.611** | **0.763** | **0.879** | **0.981** | **0** (boot: frames 1-127) | 2.43 |

Attract, no load: median 0.621, 99% 0.921, max 0.980. In play with no load the VRAM copy ends on line 12 after the
interrupt in 1,655 of 1,655 frames and the palette writes by line 18 (one frame at boot, 147, on line 96), against 22
lines of blanking.

## Game scope

| Set | Game | Map | ROM loaded | MAME flags |
|---|---|---|---|---|
| `gstream` | G-Stream G2020 | `gstream_32bit_map`, `gstream_io`; 2 x M6295 | 32.5 MB | `SUPPORTS_SAVE` |
| `x2222` | X2222 (final debug?) | `x2222_32bit_map`, `x2222_io`; 16-bit colour | 25.1 MB | `SUPPORTS_SAVE`, `NO_SOUND` |
| `x2222o` | X2222 (5-level prototype) | as `x2222`; 512 KB boot ROM | 24.6 MB | `+ IMPERFECT_GRAPHICS` |

### Scope decision

- **In scope:** all three sets (the user's choice). One CPU, one VRAM layout, one screen; X2222 differs in its map, I/O
  and pixel format, which become per-set configuration.
- **Memory:** a 64 MB or larger SDRAM module (the user's choice). `gstream` needs 36.5 MB with its work RAM, X2222 37 MB.
- **First target:** `gstream`: the only set with sound, a palette and a working MAME emulation.
- **Second target:** `x2222`, then `x2222o` (`.mra` only). Both are silent in MAME (no sound ROM dumped); `x2222o`'s
  sprite ROMs do not match its program (corrupt bosses), as in MAME.

## Hardware reality (from the driver, not assumption)

[`HARDWARE_NOTES.md`](HARDWARE_NOTES.md) holds every value below with its line in `gstream.cpp`.

### Chips

| Part | Clock | RTL |
|---|---|---|
| Hyperstone E1-32XT (`E132X`, 8 KB internal RAM) | 64 MHz (16 MHz x 4) | Vamphalf `e1_pipe.sv` |
| 2 x OKI M6295 (AD-65), banked 256 KB of 1 MB each | 1 MHz, pin 7 high | `jt6295` |
| graphics in two XC95288 CPLDs | 27 and 54 MHz crystals | from MAME's model |

### Clocks

The board: CPU 64 MHz, OKI 1 MHz, graphics crystals 27 and 54 MHz. MAME has no raster (`set_refresh_hz(60)`,
`set_size(320, 240)`, no blanking). **Pixel clock 6.75 MHz (27 MHz / 4) on a 432 x 262 raster: 15.625 kHz, 59.64 Hz**,
from the driver's sprite budget `432 * 262` (780). Unverified; MAME runs at 60.00 Hz, 0.6% faster (`docs/HACKS.md` when
the timing generator lands).

**`clk_sys` = 60.75 MHz, 9 x the pixel clock**; SDRAM on the same clock. The user's choice at the Phase 0 gate, with the
graphics fetched from DDR3 (Memory plan), after 54 MHz with the graphics in SDRAM lost 110-260 of 1,656 play frames
(Progress).

| Candidate | Multiple | Why not / why |
|---|---|---|
| 47.25 MHz | 7 x | nearest the ~48 MHz default; costs 12.5% of the CPU's throughput, which is the limit here |
| 54 MHz | 8 x | the first plan: the board's own 54 MHz crystal. Measured short (Progress) |
| **60.75 MHz** | 9 x | chosen: +12.5% CPU and SDRAM. The main board alone met 54 MHz with +2.755 ns (`9e19383`) |
| 67.5 MHz | 10 x | the lowest multiple at or above the CPU's 64 MHz (clocks.md rule 4); beyond `e1_pipe`'s timing |

The CPU breaks rule 4 (every board clock at or under `clk_sys`): `e1_pipe` is not cycle-exact to the E1 at any clock,
so it runs on every `clk_sys` clock and is held to MAME's work per frame instead (Phase 0, criterion 3).

| Enable | Ratio from 60.75 MHz |
|---|---|
| pixel | 1/9, exact |
| E1 timer (`tick`, `tick2`): 64 MHz | 256/243: a tick every clock and a second in 13 clocks of 243, exact |
| M6295 x 2: 1 MHz | 4/243, exact (an accumulator) |
| SDRAM refresh | one per chip every 7.8125 us: 474 clocks, alternating chips: 237 |

### Interrupts

Vblank on INT1 (`irq0_line_hold`; MAME input line 0 is `INPUT_INT1`), held until taken. The E1 timer is set up
(`TPR` 0x003E0000) with its compare far ahead (`TCR` 0x80000000) in play.

### Memory map

`gstream_32bit_map` and `x2222_32bit_map` as in HARDWARE_NOTES. Per set: `gstream` has the data ROM at 0x4e000000,
palette RAM and scroll registers at 0x4f000000-0x4fe00003, backup RAM; X2222 has RAM at 0x40000000, its scroll
registers at 0x4fa00000-0x4ff00003, plain RAM at 0xffc00000, a 1 MB boot ROM.

### Video

From `screen_update` (750-811): black, then tilemaps 2, 1, 0, then sprites 0..831 in order, pen 0 transparent
throughout, no priority bits, no flip. Tilemaps: 16 x 16 entries of 32 x 32 tiles in VRAM bits 31:16, 9-bit scroll.
Sprites: code, x, y, colour in bits 15:0 of four dwords; each sprite drawn at its four wrap positions, of which at most
one is visible. `gstream`: BGR565 palette RAM, colour `0x1000 + 0x400*layer + pal*256 + pen` for tiles, `col*256 + pen`
for sprites, everything 2 pixels left (`m_xoffset`). X2222: 16-bit pixels shown directly, no offset.

### Sound

`gstream` only: two M6295s at 1 MHz (7,575.8 Hz), each banking 256 KB of its 1 MB from I/O 0x100c, mixed mono at
equal gain. X2222: none (no ROM dumped; `x2222_sound_w` is ignored in MAME).

### Protection

None in the driver.

### Per-game configuration

The `.mra` mod byte selects the map: 0 `gstream`, 1 X2222 (both sets; `x2222o`'s boot ROM is loaded at 0x80000 of the
1 MB region, the rest zero, as MAME). Through it: the memory and I/O decode, the scroll register addresses, the colour
path (palette or direct), `m_xoffset`, the NVRAM (backed up on `gstream` only), the input ports, the DIPs, sound on or off.

## Component reuse map

Every source below was located and its header read; files are copied with a `PROVENANCE.md`.

| block | plan | source |
|---|---|---|
| E1-32X CPU | `e1_pipe.sv`, `e1_regram.sv` (and `e1_cpu.sv` for the benches) copied unchanged; kept in step by Eolith's `vendor.json` / `vendor_sync.py`, changes made in Vamphalf first | `Arcade-Vamphalf_MiSTer/rtl/e1/` at `8f1f21c` (the files' last change), GPL-3.0; written there from MAME `e132xs` (BSD-3-Clause) |
| CPU memory unit | `rtl/gs_cpumem.sv` generated from `vh_cpumem.sv` by exact text substitutions (`scripts/gen_gs_cpumem.py`, after Eolith's `gen_eo_cpumem.py`): this map's decode, the internal RAM, VRAM, palette, scroll and NVRAM ports, cached work RAM, boot and data ROM | Vamphalf `rtl/vh_cpumem.sv`, `rtl/vh_cache.sv`; Eolith `scripts/gen_eo_cpumem.py` |
| E1 benches and MAME trace tools | the conformance suite (`e1_regress.py`, `sim/e1_tb`), the MAME trace tools (`mame_e1_trace.py`, `e1trace.lua`, `e1trace_convert.py`), the whole-board bench pattern (`sim/sys_tb`) | Vamphalf `scripts/`, `sim/` |
| SDRAM controller | `sdram.sv` (Sorgelig's, burst 4, double read on all three ports, burst writes) | Vamphalf `rtl/memory/` (KonamiGX lineage, PROVENANCE there), GPL-3.0-or-later |
| ROM loading | `vh_rom_loader.sv` + `ddram_phy.sv`: the image through DDR3 at load time only | Vamphalf `rtl/memory/` |
| Sprites | Vamphalf's per-scanline 16 x 16 8 bpp engine (`vh_video.sv`, `vh_gfxport.sv`: the same 16-byte row format, four requests in flight on port 0), with this board's entry format, 832-entry list, wrap, 5-bit colour and an empty-tile table. Chosen over `jtframe_objdraw` because it is the engine Vamphalf's sets run on the board, for this exact tile format | Vamphalf `rtl/video/` |
| Tilemaps | new: a per-line engine for three 32 x 32 layers, written from `draw_bg` (721-748) | none found: no other core draws this chip |
| Palette, mixer, X2222 colour | new, from `screen_update` and `drawgfx_transpen_x2222` | |
| M6295 x 2 | `jt6295` with `oki_rom_bridge.sv` and `sample_cache.sv`; the bank register from `gstream_oki_banking_w` | Vamphalf `rtl/sound/` (from Fuuki; jotego `jt6295` `7d76b0b`, GPL-3.0) |
| Video out, CRT Adjust, rotation | `sys/arcade_video.v`, rmonic79 `crt_adjust.sv`, Sorgelig `screen_rotate_two.sv` | Vamphalf `rtl/video/` |
| NVRAM save | `ioctl_upload` of the 8 KB backup RAM, `<nvram index="4" size="8192">` | Arcade-JalecoMS32_MiSTer `MS32.sv` (no `hiscore.dat` entry for this driver) |
| Pause, keys, debug | Fuuki `pause_control.sv`; `rtl/mame_keys.sv` (template); Vamphalf `rtl/debug/` (`issp_probe.sv`, `vh_trace.sv`) | |

## On-chip RAM budget

Estimates in M10K blocks (553 on the device), to be replaced by fit reports.

| Memory | Size | M10K |
|---|---|---|
| VRAM, CPU side and render side (the latch, below) | 2 x 16 KB | 32 |
| Palette (CPU port and renderer port) | 28 KB | 28 |
| Empty-sprite-tile table | 64 Kbit | 8 |
| Line buffers, double: three tile layers and sprites | 4 x 2 x 512 x 13 bits | 8-16 |
| Backup RAM | 8 KB | 8 |
| E1 internal RAM | 8 KB | 8 |
| I-cache 16 KB, D-cache 4 KB, tags | | about 24 |
| OKI sample caches | | 2 |
| Framework, OSD, scaler, CRT Adjust | | about 170 (Vamphalf's 467 less its own memories) |
| **Total** | | **about 300 (54%)** |

Nothing here is near the limit; CRT V-Size can stay.

## Memory plan

**Graphics from DDR3 during play** (the user's choice at the Phase 0 gate). The stated reason, measured: the tile and
sprite fetches on the SDRAM took the E1 from 2.44 to 3.13 clocks an instruction and lost 110 of 1,656 play frames at
the census's average load (Progress). The `.mra`'s image is put in DDR3 at 0x30000000 by the HPS at load time (fast
loading), so the graphics are already there; the video reads them in place and `vh_rom_loader` copies only the rest
to SDRAM. The video is DDR3's only client during play besides the HDMI rotator; the rotator's buffer goes above the
image, and the two are arbitrated.

SDRAM: the CPU's ROMs, the samples and the RAMs, all on 60.75 MHz through `sdram.sv`; 13 MB, so a 32 MB module now
holds it. Layout (`rtl/gs_sdram_map.svh`, which `scripts/build_mra.py` reads): the image's layout in DDR3, of which
the first 5 MB (`SD_SDRAM_END`) is copied to SDRAM; the RAMs are SDRAM only. The RAMs are cleared at load: MAME's are
zero at power-on and SDRAM keeps whatever the last core left.

| Region | Offset | Size | Contents |
|---|---|---|---|
| `SD_BOOT` | 0x0000000 | 1 MB | the boot ROM's window (`gstream` 512 KB at +0x80000; `x2222o` at +0x80000) |
| `SD_DATA` | 0x0100000 | 2 MB | `gs_prg_02`, the CPU's byte order |
| `SD_OKI1`, `SD_OKI2` | 0x0300000 | 2 x 1 MB | sample ROMs |
| `SD_SPR` | 0x0500000 | 16 MB | sprite tiles (X2222: 16-bit pixels): DDR3 only |
| `SD_TILE0..2` | 0x1500000 | 3 x 4 MB | tile layers 0, 1, 2 (X2222: 16-bit pixels): DDR3 only |
| `SD_WRAM` | 0x0800000 | 4 MB | work RAM, SDRAM only (the image's sprite addresses in DDR3) |
| `SD_XRAM` | 0x0c00000 | 4 MB | X2222's RAM at 0x40000000, SDRAM only |

SDRAM ports, fixed priority: 1 sound (two OKIs through the sample caches), 2 the CPU's line fills, write buffer and
prefetch, and the download; port 0 is free.

**Fetch arithmetic per line, `gstream`, from DDR3**: a line is 432 x 9 = 3,888 clocks of 60.75 MHz, 64 us. Tiles: 3
layers x 11 tiles x 32 bytes = 1,056 bytes; sprites at most 74 rows (the census, play) of 16 bytes = 1,184 bytes:
2,240 bytes a line, 35 MB/s. The cost is DDR3's latency, not its bandwidth: requests are issued ahead with several in
flight (the tile rows a line ahead, sprite rows as the scan finds them). Measured in Phase 1 against the line period.
X2222 doubles the bytes (32-byte sprite rows, 64-byte tile rows); its census comes before its RTL (Phase 4).

## Design decisions

**Follow MAME, including where MAME is wrong, and write down every place that is.** There is no
PCB here. MAME is the accuracy target and its acknowledged guesses are inherited deliberately. Each
goes in `docs/MAME_KLUDGES.md` when it is implemented, with what MAME does, what the hardware is
suspected to do, and what would settle it.

**Where a vendored module and MAME disagree, record it and keep the module.** A silicon-derived
disagreement is evidence about the chip; MAME's is evidence about MAME. It goes in
`docs/MAME_KLUDGES.md`, not into a "fix", until one side is shown to describe the chip.

**Every approximation of this core's own goes in `docs/HACKS.md`** in the commit it lands, with
what would make it correct. A hack that is not written down is a bug nobody will find.

**Transcribe the reference literally first, then look for the chip.** Build MAME's version, get
pixel-exact (or trace-exact) agreement with captured references, and only then experiment — with
the experiment on an OSD switch so it is an A/B, not a rebuild.

**One `.rbf` for all games.** Per-set differences are `.mra` mod-byte configuration.

**Two Quartus revisions, `GStream_stp` and `GStream`,** differing only by a `DEBUG_ISSP` macro.
See [`WORKFLOW.md`](WORKFLOW.md).

**Licence: GPL-3.0.** `jt6295`, `sdram.sv` and the E1 RTL are GPL-3.0. Every dependency, what it obliges and the
release checklist go in [`THIRD-PARTY.md`](../THIRD-PARTY.md) with the first vendored file. `sys/` is never edited.

**Per-scanline rendering from buffered VRAM.** The default shape, as the boards worked:
the list latched once a frame at the point the video-write sweep identifies, a per-scanline
engine, a double-buffered line buffer. A frame buffer only where the driver shows the board had
one; cite it here.

**No multiplies, no divides, in 2D pipelines.** Shifts, masks, adds and accumulators; WORKFLOW §14.

**The E1 is changed only in Vamphalf.** This core copies `rtl/e1` unchanged and checks it with `vendor_sync.py`; a CPU fix
found here is made in Vamphalf and copied back, as Eolith does.

**No sprite frame buffer, though the board may have one.** MAME draws sprites with the tilemaps in the same frame and
lists "sprite lag (sprites need buffering?)" as a TODO (19); the PCB's four LP621024 SRAMs (512 KB) beside the graphics
section (dump notes, 115-130) could be a double frame buffer. Following MAME, sprites are drawn per line with no lag;
the suspicion goes in `docs/MAME_KLUDGES.md`.

**VRAM and the scroll registers are latched together once a frame; the palette is read live.** The sweep: the CPU
rewrites all 4,096 VRAM dwords on MAME's lines 0-6 after the vblank interrupt, the six scroll registers on line 6 and the
palette on lines 6-8, and nothing later; on the board that is inside vertical blanking. The core's CPU is slower: the same
copy at 2.5-3 clocks an instruction takes an estimated 17-21 lines, and the palette writes after it end by about
line 26, against 22 lines of blanking. The render side gets a copy of
VRAM and the scrolls at the end of blanking if the core's copy finishes inside it (measured in the whole-board bench,
Phase 0); otherwise the latch point and its cost go to the user with the measurement. The renderer never reads the copy
the CPU is writing.

**The sprite scan skips empty tiles.** About 800 of the 832 entries sit on screen with code 0; a 65,536-bit table of
all-zero sprite tiles, filled while the ROM loads, lets the scan skip them. Exact: an empty tile draws nothing.

**Sprites beyond the line's budget are counted, not hidden.** A saturating overrun counter on the debug page; the
census's worst line (74 sprites) is the bench case.

## Pitfalls that already bind decisions here

| Entry | What it binds here |
|---|---|
| [Vamphalf] `irqN_line_hold` names MAME's input line N, not the CPU's interrupt N | vblank is INT1 here (`irq0_line_hold`); Vamphalf's sets use INT2 |
| [Eolith] A CPU vendored from another core can carry that core's memory map | `e1_pipe.sv` 1760 names Vamphalf's cached regions (work RAM below 4 MB, 0x4001xxxx-0x4003xxxx); checked against this map before the first boot, and data accesses compared with MAME's bus trace, not only PCs |
| [MS32] A CPI measured on the power-on RAM test is a CPI of the RAM test | the throughput gate is measured on play frames 1501-1560 and 2701-2760 |
| [Vamphalf] A `ROM_REGION32_BE` graphics region is drawn in host byte order | `init_x2222` builds its graphics as host-order `uint32_t`; the X2222 image is checked against MAME frames, not against `ROM_START` alone |
| Never hold the memory path in the core reset | the SDRAM side resets on the PLL lock only |
| [Seta] Latch the sprite list and the video registers at the same point unless evidence separates them | VRAM and the scroll registers latch together |
| [GX] A per-line object scan that runs out of time drops sprites without an error | the overrun counter |
| [HyperNG64] Check a large set's regions for byte-identical copies before sizing memory | done: the X2222 sets share all graphics; `gstream`'s OKI bank 0 duplicate is not worth removing at 64 MB |

## Phased roadmap

**Phase 0 — The CPU on this board, and its throughput. The gate.**

1. **Vendored modules' own tests pass unchanged on arrival**: the E1 conformance suite (`e1_regress.py`, the seeds
   Vamphalf runs, 0 and 3 wait states), `jt6295`'s and `sdram.sv`'s benches where they have them.
2. **`gs_cpumem` generated and the board boots in the whole-board bench**: `gstream` from its `.mra` image on the real
   SDRAM controller matches MAME's trace for 1,000,000 instructions from reset, PCs and data accesses.
3. **Throughput in play**: inputs replayed from MAME, port 0 loaded at the census's worst line (140 double reads a line),
   clocks from the vblank interrupt to the idle loop per frame over frames 1501-1560 and 2701-2760, and the line on which
   the VRAM copy and the palette writes end. Pass: the worst frame under 90% of the 905,472-clock frame. Otherwise to the
   user with the numbers and the fallbacks (HARDWARE_NOTES, Feasibility).
4. **Fmax and area** of CPU and memory unit at 54 MHz (`rtl/synth_check/`), constraint committed with the result.

**Phase 1 — Video against a software model.**

`scripts/render_model.py` reproducing `screen_update` (wrap, `m_xoffset`, the 832-entry limit, the palette), pixel-exact
against MAME captures. Then the RTL in Verilator against the model: the tile engine, the sprite engine from Vamphalf's,
the empty-tile table, palette and mixer, the VRAM/scroll latch. Exit: `gstream` frames pixel-identical to MAME's for a
captured set of scenes (attract, stage 1, the boss at 2700, the census's worst-line frame), overrun counter at zero.

**Phase 2 — Hardware bring-up of `gstream`.**

SDRAM map, the DDR3 loader, `.mra` generation (with `<mameversion>`), the empty-tile table filled at load, inputs (MAME's
keys and the pads, real button names from the manual), the backup RAM with the default image and NVRAM save, the ISSP
probe and the OSD debug page, the CPU's Pause. The standard feature set: CRT Adjust (with V-Size), fast DDR3 ROM loading,
HDMI scaling and crop, HDMI rotation, flip screen (a fake DIP: the game has none) checked against the unflipped frame
turned 180 degrees, options hidden where they do not apply. Exit: G-Stream boots and plays on a DE10-nano with the
throughput Phase 0 measured, silent.

**Phase 3 — Sound.**

Two `jt6295`s on 1/54 enables, each behind `oki_rom_bridge` and the sample cache on port 1, the bank register at I/O
0x100c, status reads, mono mix. Exit: MAME's OKI command trace replayed on the bench matches; on the board, judged by ear
against MAME.

**Phase 4 — X2222 and X2222 (prototype).**

First the measurements: busy time and instructions per frame (the speed-up PCs in `x2222_speedup_r`/`speedup2_r`), the
census and sweep on X2222's map. Then the map, the I/O (DSW, the IN4 toggle as MAME does it), 16-bit sprite and tile
rows, direct colour, the `.mra` rearrangement checked against MAME frames. Exit: both sets play on the board as in MAME,
silent; `x2222o`'s corrupt bosses as in MAME.

**Phase 5 — Savestates, state dumps and cheats.** Optional but desirable, after Phase 4; the RTL is written for it from
Phase 1 (reachable RAM ports, `docs/STATE.md`). The state dump comes before the savestate.

## Verification strategy

- **MAME is a reference generator, driven from scripts, not a thing to eyeball.** Boot traces, VRAM
  and register dumps at known frames, palette dumps, register-write logs. WORKFLOW §9 applies.
- **The software model comes before the RTL.** The model is checked against MAME first; the RTL
  against the model.
- **Every vendored module is verified against MAME before it is wired to anything**, and its own
  testbench is the regression for every later change to it.
- **Layouts are verified before ROMs are involved**: every `gfx_layout` gets the "every bit of a
  tile exactly once" check.
- **`.mra` files are generated, not written**, re-read byte-for-byte against an image built from
  `ROM_START`, and gated on an XML well-formedness check before deploy.
- **Worst cases are measured in the RTL**, not modelled: saturating counters with no reset port,
  each paired with a total.

## Repository setup

Seeded from **MiSTer-devel/Template_MiSTer**, `Template.*` renamed to `GStream.*` and split into
the `GStream_stp` and `GStream` revisions; the Quartus 13 project dropped. Quartus **17.0.2**.
Conventions are in [`WORKFLOW.md`](WORKFLOW.md) and `CONVENTIONS.md`.

## Open items

1. **The raster.** 6.75 MHz, 432 x 262, 59.64 Hz is read from the driver's sprite budget and the 27 MHz crystal. A PCB
   measurement or recording would settle it; until then it is a `docs/HACKS.md` entry.
2. **CPU throughput.** Estimated 67-85% of a frame for the worst sampled frame; closed by Phase 0, criterion 3.
3. **Where the VRAM latch goes.** Closed by Phase 0's measurement of when the core's VRAM copy ends.
4. **Palette writes past entry 0x1c00.** MAME's palette ends there (an `assert`); the core keeps all 28 KB as RAM. A
   palette capture shows whether the game writes beyond it.
5. **Button names and the S3 DIP bank.** MAME declares four buttons a player and no DIPs; the manual or a PCB says what
   the game uses.

## Next steps

1. ~~The user's approval of this roadmap.~~ Approved.
2. ~~Phase 0.~~ Passed (Progress).
3. ~~Phase 1.~~ Met in simulation (Progress).
4. Phase 2: the top level (`GStream.sv`): DDR3 shared by the loader, the video and the rotator; the `.mra`; inputs,
   NVRAM, the standard features; the first build on the board.

Phase 2, in progress: `GStream.sv` (after Vamphalf's `Limenko.sv`), `rtl/memory/gs_ddr_arb.sv` (DDR3: the load-time
client, then the video's reads and the rotator's writes in turn), `rtl/memory/gs_et_scan.sv` (the empty-tile table from
the image in DDR3; `sim/et_tb`: 8,192 of 8,192 bytes equal to the table computed from the image, 35 ms), the PLL at
60.75 MHz, `releases/G-Stream G2020.mra` (`scripts/build_mra.py`: identical to ROM_START; `validate_mra.py` OK).
Buttons: in MAME, in play, button 1 fires and button 2 sets off the bomb; 3 and 4 showed nothing held alone, and the game's
input test names all four PUSH1-4 (`debug/btn`, `debug/svc2`). `sim/sys_tb` now runs the video against a DDR3 model:
boot frames 8, 10, 12, and in play (inputs as `scripts/mame_busy.py`, DDR3 latency 60 clocks, port busy 30%) every
100th frame from 200 to 1800, 17 of 17, identical to the model on the state they were drawn from
(`scripts/sys_video_check.py`); no video overrun, longest pass 1,419 clocks; CPU busy median 0.549, 99% 0.744, max 0.940,
no frame lost after boot (frames 1-127). Not yet
built at first: the first Quartus build waited for the machine. First build (`GStream_stp`, `18042c7`, seed 1): 25,822
ALMs (62%), 204 of 553 RAM blocks, 43 DSP blocks; every clock met, worst `clk_sys` setup +1.108 ns, worst HDMI setup
+0.448 ns, worst hold +0.218 ns. **On the board** (deployed as `GStream_30000001.rbf`, launched through the menu core):
G-Stream boots to its title screen (`docs/screenshots/gstream/title_board_18042c7.png`, the core's native frame) and
runs (the user). Not yet checked there: the backup RAM's save, flip, CRT Adjust, rotation.

Frames on the board (probe P, `89633b8`; `scripts/read_issp.py P`): after a clear in play, 10,234 frames, 0 lost, 0
without a VRAM update, the busiest 963,437 of 1,018,656 clocks (94.6%), 7 over 90%.

Sound. The OKI commands and banks on the bench (`sim/sys_tb +okilog`) are MAME's (`scripts/mame/okilog.lua`) byte for
byte, shifted by the inputs' timing; the power-on sound's length and pitch are MAME's (correlation 0.95). On the board
(probe S, `3499733`): the 2 MB of sample ROMs read back from SDRAM equal the image, twice (`scripts/oki_sum.py`); no
ADPCM byte late, the longest wait for one 65 clocks of the 243 at least. The sample data's bit order: of the 40,320
orderings, only the ROMs' own decodes four 8 KB stretches without the ADPCM signal reaching its clamp
(`scripts/oki_bitorder.py`; one stretch also clean with the nibbles swapped). By ear (the user): brighter and noisier
than MAME; the output now goes through a 4th-order low-pass at 3.5 kHz (`e7f1709`, OSD Audio Filter), equal to
`scripts/snd_filter.py`'s model over 1,206,870 samples. Not yet judged on the board.
