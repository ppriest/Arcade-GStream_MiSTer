# GStream: hardware notes

What the board is, from MAME and from measurements of MAME, each fact with where it came from.

Source: MAME `src/mame/promat/gstream.cpp` at `96962b96c89` (`mame0289-662`; against the `mame0289` tag the
driver differs only by the screen-device rename, `774a180df2b`, and the CPU by one `std::rotl`, `63c2ec0ccfe`), and
`mame -listxml` from MAME 0.289. Line numbers below are that file's. Everything here is MAME's model unless marked
otherwise. Measurements were taken with this repository's scripts; the raw outputs are in `debug/` (not committed)
and the commands are given so they can be rerun.

## Sets

| Set | Game | Map | ROM loaded (bytes) | MAME flags |
|---|---|---|---|---|
| `gstream` | G-Stream G2020 (2002, Oriental Soft Japan) | `gstream_32bit_map`, `gstream_io` | 34,086,912: boot 512 KB, data 2 MB, sprites 16 MB, tiles 3 x 4 MB, OKI 2 x 1 MB, NVRAM default 8 KB | `MACHINE_SUPPORTS_SAVE` |
| `x2222` | X2222 (final debug?) (2000, Oriental Soft / Promat) | `x2222_32bit_map`, `x2222_io` | 26,352,640: boot 1 MB, sprites 14.9 MB, tiles 9.2 MB; `test.hye` (1,125,850, the source the boot ROM was built from, region `misc`) is not mapped | `MACHINE_SUPPORTS_SAVE \| MACHINE_NO_SOUND` |
| `x2222o` | X2222 (5-level prototype) | as `x2222` | `older.bin` 512 KB at 0x80000 of the 1 MB boot region; graphics as `x2222` (sprites `BAD_DUMP`, 1030) | `+ MACHINE_IMPERFECT_GRAPHICS` |

Region CRCs (`-listxml`): `x2222` and `x2222o` share every graphics ROM and differ only in the boot ROM; `gstream`
shares nothing with them. Within `gstream`, `gs_prg_02.u197` is 0xFF from 0x80000 to its end (1.5 MB), and the first
256 KB bank of `oki1` and `oki2` are byte-identical (CRC `dda40e6b`); the other three banks differ
(checked against the zip with a one-off script). `x2222`'s sound ROM is `NO_DUMP` (992): the X2222 sets are silent.

## CPUs and chips

| Tag | Part | Clock | Role | Existing RTL |
|---|---|---|---|---|
| `maincpu` | Hyperstone E1-32XT (`E132X`, 8 KB internal RAM, `iram_8k_map`, e132xs.cpp 126, 279-284) | 64 MHz: 16 MHz x 4 internal multiplier (835, 864) | everything | `Arcade-Vamphalf_MiSTer/rtl/e1/e1_pipe.sv`: same `E132X` device as `aoh` there (vamphalf.cpp 1349) |
| `oki1`, `oki2` | 2 x OKI M6295 (AD-65 clones) | 1 MHz, pin 7 high (856, 858) | ADPCM, mono | jotego `jt6295`, vendored in Vamphalf and Fuuki |
| | 2 x Xilinx XC95288 CPLD | | the graphics section (dump notes, 110-122) | none: the video is written from MAME's model |

## Clocks

| Clock | Value | Source |
|---|---|---|
| CPU | 64 MHz (16 MHz crystal x 4) | 28, 835 |
| OKI | 1 MHz crystal; sample rate 1 MHz / 132 = 7,575.8 Hz (pin 7 high) | 28, 856 |
| Graphics | 27 MHz and 54 MHz crystals "near GFX section" | 31-32, 121 |
| Pixel clock | **not in MAME**: `set_refresh_hz(60)`, `set_size(320, 240)`, `set_visarea_full()`, `set_vblank_time(0)` (844-847) | |

The only raster figure in the driver is the sprite budget's `432 * 262` (780), commented "TODO : measure screen
size, related to that?". 27 MHz / 4 = 6.75 MHz on a 432 x 262 raster gives 15.625 kHz and 59.64 Hz. Unverified; the
roadmap's Clocks section builds on it and `docs/HACKS.md` will carry it.

## Video

Display: 320 x 240 visible, 60 Hz, ROT270 (1134-1136); no blanking in MAME's model. Aspect 4:3 (3:4 rotated).

**Order and mixing** (`screen_update`, 750-811): the bitmap is filled with black (RGB 0, not a palette entry, 772),
then tilemap 2, 1, 0, then sprites, each with pen 0 transparent. No priority bits, no blending, no flip register.

**Tilemaps** (`draw_bg`, 721-748): three layers; layer n's 16 x 16 entries are VRAM dwords `0x100*n .. 0x100*n + 0xff`
(`m_vram + 0x400*n/4`, 775-777), bits 31:16 (bits 15:0 belong to the sprites). Entry: code bits 11:0, palette bits
15:14, bits 13:12 unused. Tiles are 32 x 32, 8 bpp, one byte a pixel, 32-byte rows, 1 KB per tile (`layout32x32`,
544-553); the map wraps at 512 x 512. Scroll x and y, 9 bits each (726-727), written to bits 31:16 of their registers.
Screen pixel (sx, sy) of layer n shows map pixel `((sx + xoff + scrollx) & 511, (sy + scrolly) & 511)`, `xoff` = 2 for
`gstream` (1094), 0 for the X2222 sets (1128). Colour: `0x1000 + 0x400*n + pal*256 + pen` (`gfx_gstream`, 555-560:
layer 0 is region `gfx2` = `gs_gr_01/02`, layer 1 `gfx3` = `gs_gr_03/04`, layer 2 `gfx4` = `gs_gr_05/06`).

**Sprites** (779-809): entry i (0..831) is VRAM dwords `4i .. 4i+3`, bits 15:0: code (16 bits; 65,536 tiles in the
16 MB `gfx1`), x (bits 8:0), y (bits 7:0), colour (bits 4:0). Only the first 832 entries are drawn: MAME charges
8 + 128 per entry against `432 * 262` and stops (780-785), a guess ("can't be drawable everything"). Each sprite is
drawn at (x - xoff, y), (x - xoff, y - 256), (x - xoff - 512, y) and (x - xoff - 512, y - 256): the wrap. 16 x 16,
8 bpp, 16-byte rows, 256 bytes a tile (`layout16x16`, 532-541); no flip, no zoom, no priority; later entries over
earlier ones. Colour `col*256 + pen`. `gfx1` is four 4 MB banks, each two 2 MB ROMs word-interleaved
(`ROM_LOAD32_WORD`, 898-906).

**Palette**: RAM at 0x4f400000-0x4f406fff (28 KB, 280), two entries per dword, the even entry in bits 31:16;
`BGR_565`, R = bits 4:0, G = 10:5, B = 15:11, each widened by bit replication (emupal.cpp 315, emupal.h 130-136).
MAME's palette has 0x1c00 entries (850); a sprite colour of 28-31 would read past it (undefined in MAME, an
`assert` only, palette.cpp 348). The game uses colours 0-13 (census below).

**X2222's colour**: 16-bit direct colour, no palette RAM (`PALETTE(..., BGR_565)`: 65,536 fixed entries, 879). Each
pixel is 16 bits from two bytes, transparent when 0 (`drawgfx_transpen_x2222`, 581-719). `init_x2222` rearranges the
ROMs (1098-1129): a sprite pixel n comes from ROM bank `n & 3` (`spr1k`/`spr2k`), word `n >> 2`, low byte even; a tile
pixel n from `bg?1` for even n and `bg?2` for odd n, word `n >> 1`. Tile codes wrap at 2,048, sprite codes at
32,768 (`code %= gfx->elements()`, 585). Layer n uses `gfx2+n`: layer 0 `bg1` (`bg31/32`), 1 `bg2` (`bg21/22`), 2
`bg3` (`bg11/12`). X2222's program ROM does not match its sprite ROMs: the bosses are corrupt (9).

**MAME's own notes**: "sprite lag (sprites need buffering?)" and "sprite wraparound is imperfect" (19-20).

## Memory map

`gstream_32bit_map` (272-287):

| Range | What |
|---|---|
| 0x00000000-0x003fffff | work RAM, 4 MB |
| 0x40000000-0x40ffffff | unmapped (commented out: "lots of data gets copied here if present, but game runs without it", 275) |
| 0x4e000000-0x4e1fffff | data ROM `gs_prg_02`, 2 MB, word-swapped (896) |
| 0x4f000000 / 0x4f200000 | scroll x / y of layer 2 (bits 31:16) |
| 0x4f400000-0x4f406fff | palette RAM |
| 0x4f800000 / 0x4fa00000 | scroll x / y of layer 0 |
| 0x4fc00000 / 0x4fe00000 | scroll x / y of layer 1 |
| 0x80000000-0x80003fff | VRAM, 16 KB: tilemaps in bits 31:16, sprites in bits 15:0 |
| 0xc0000000-0xdfffffff | the CPU's internal RAM, 8 KB mirrored |
| 0xffc00000-0xffc01fff | backup RAM, 8 KB, battery-backed (`NVRAM`, default image `gstream.nv`) |
| 0xfff80000-0xffffffff | boot ROM `gs_prg_01`, 512 KB |

I/O (`gstream_io`, 354-363); the port is the effective address >> 13 (e132xs.cpp 1555), one dword each:

| Port | Read | Write |
|---|---|---|
| 0x1000 | IN0: P1 (bits 0-7 up/down/left/right, buttons 1-4), coin 1 (9), start 1 (10), service 1 (11), test (15) | |
| 0x1004 | IN1: the same for P2; bit 15 mirrors test (`mirror_service_r`) | |
| 0x1008 | IN2: coin 1, coin 2, start 1, start 2, test mirrored in bits 0-3, 6 (`gstream_mirror_r`, 235-251) | |
| 0x100c | | OKI banks: oki1 = `(b6 & !b7) << 1 \| (b2 & b3)`, oki2 = `(b4 & !b5) << 1 \| (b0 & b1)` (339-340); each bank 256 KB of the chip's 1 MB |
| 0x1010 | | ignored (writes 0 or 0x81, "some clocking?") |
| 0x1014 | oki1 status, bits 7:0 | oki1 command |
| 0x1018 | oki2 status | oki2 command |

`x2222_32bit_map` (366-383): work RAM as above, RAM 4 MB at 0x40000000, VRAM as above, scroll y/x of layer 1 at
0x4fc00000/0x4fd00000, layer 2 at 0x4fa00000/0x4fb00000, layer 0 at 0x4fe00000/0x4ff00000, plain RAM at 0xffc00000
(the NVRAM device is commented out, 869), boot ROM 1 MB from 0xfff00000. `x2222_io` (392-400): P1 0x1000, P2 0x1001,
SYS 0x1002, DSW 0x1004, IN4 0x100d (bit 7 toggles on every read, `x2222_toggle_r`, "or the game hangs when starting"),
write 0x100a ignored (`x2222_sound_w`).

## Interrupts

Vblank raises input line 0, INT1 (`irq0_line_hold`, 838; `INPUT_INT1 = 0`, e132xs.h 107), held until taken. In
play (frame 1500) the CPU's registers read `FCR` = 0xEF7FFFFF, `TPR` = 0x003E0000, `TCR` = 0x80000000, `MCR` =
0xFFDE00C8 (MAME state, this session): the timer compare is far ahead, but the timer must still count at the
CPU's 64 MHz rate.

## Inputs, DIPs, backup

- `gstream`: no DIP switches in MAME. The PCB has S3, a two-position DIP bank of unknown use, and S2, a toggle that
  resets the high scores (dump notes, 124-125); neither is emulated. Four buttons a player are declared (408-411).
- `x2222`: DSW (Free Play, Difficulty, Lives, Coin A), SYS and IN4 with unknown DIP bits (462-528).
- High scores live in `gstream`'s 8 KB backup RAM; MAME's `hiscore.dat` has no entry for the driver. Saved as NVRAM
  (`<nvram index="4" size="8192">`, as Arcade-JalecoMS32_MiSTer does).

## Sound

Two M6295s, each with its own 1 MB region (`oki1` = `gs_snd_01/02`, `oki2` = `gs_snd_03/04`), the 256 KB bank from I/O
0x100c, both mixed to one channel at gain 1.0 (856-858). MAME's note that the game "reads the status register all the
time" (39-41) describes polling, not a fault in the model.

## Measurements in MAME

All on `gstream`, MAME 0.289, coin at frame 600 then Start, P1 button 1 tapped from frame 900 (frames 1500 and 2700 are
in play: `debug/icount/snap/`).

- **CPU busy time** (`python scripts/mame_busy.py gstream d1ee0 c0001592 --frames 3600 --coin 600 --fire 900`; the idle
  poll is `init_gstream`'s speed-up address and PC, 1060-1065): fraction of each frame before the CPU settles in the idle
  loop, 3,540 frames after boot: median 0.209, 90% 0.256, 99% 0.286, max 0.586. The 15 overruns are frames 60-74 (boot);
  none in play.
- **Instructions per frame** (`python scripts/mame_icount.py gstream c000158c-c0001594 --start <f> --frames 60`, every
  instruction traced, `-nodrc`; the idle loop is the three instructions at 0xc000158c-0xc0001594): frames 1501-1560
  (stage 1) median 187,010, max 213,361; frames 2701-2760 (a boss) median 241,370, max 272,156. MAME charges about 1.3
  cycles per instruction of this work. Most of it runs from the internal RAM (0xc0000000 blocks lead the PC histogram,
  `debug/icount/gstream_*.txt`).
- **Write sweep** (`python scripts/write_timing.py gstream --skip 600 --frames 1800`, and `--coin 600 --skip 1500 --tag
  _play`; MAME's raster is 240 lines from the interrupt): every frame the CPU rewrites all 4,096 VRAM dwords (both halves,
  32-bit writes) on lines 0-6 after the vblank interrupt, then each scroll register once on line 6, then the palette (51
  writes a frame in attract, 144 in play) on lines 6-8. Nothing is written for the rest of the frame. Attract and play
  agree. Raw: `debug/wtiming/gstream*.txt`.
- **Sprite and tile census** (`python scripts/vram_census.py gstream` and `--coin 600 --skip 1500 --tag _play`, 1,800
  frames each): about 800 of the 832 drawn entries are parked on screen with code 0, an empty tile (4,026 of the 65,536
  sprite tiles are empty), so 720-823 placements cross a visible line. Counting only non-empty tiles, a visible line
  crosses at most 52 (attract) and 74 (play) sprites, 99th percentile 47 and 51. Sprites with visible pixels per frame:
  up to 525 (attract), 413 (play). Colours used: 0-13. Tile palette select (bits 15:14) is always 0 and bits 13:12 never
  set, in both runs.

## Feasibility

The board is a 64 MHz 32-bit CPU with three 8 bpp tile layers and 16 MB of sprites; MAME's idle-loop speed-up hides how
hard the CPU works. Three unknowns decide whether the core plays as MAME does.

1. **CPU throughput (blocking).** The worst sampled frame needs 272,156 instructions. `e1_pipe` runs 2.23-2.83 clocks an
   instruction in play on Vamphalf's sets (Vamphalf ROADMAP, Phase 7 table, `5dab2e1`), with its memory unit and one SDRAM.
   At `clk_sys` = 54 MHz and a 432 x 262 raster (905,472 clocks a frame) that is 607,000-770,000 clocks: 67-85% of the
   frame for the worst frame, 58-75% for the boss median. The nearest comparison is Age Of Heroes on the Vamphalf core,
   the same `E132X` at 80 MHz: its MAME busy fraction is a median 0.068 and 99th percentile 0.224, and it plays on the
   board with occasional tearing from CPU speed (Vamphalf ROADMAP, Phase 5). G-Stream's median is three times aoh's.
   What is not known is G-Stream's own clocks per instruction: its memory pattern, and three tile layers taking SDRAM time
   that Vamphalf's sprites alone did not. **Closing measurement:** Phase 0 runs `gstream` on `e1_pipe` and the new memory
   unit in the whole-board bench, with the video's SDRAM traffic, over MAME's frames 1501-1560 and 2701-2760, and reports
   clocks to the idle loop per frame. Fallbacks, each to the user with numbers: `clk_sys` at 60.75 MHz (9 x the pixel
   clock, +12.5%; `e1_pipe` met 56 MHz with +1.708 ns, Vamphalf `8f1f21c`, so about 62 MHz is the estimate, unproven);
   graphics fetched from DDR3 during play so the CPU has the SDRAM; work-RAM areas the profile shows hot moved to block RAM.
2. **Video bandwidth: fits, with the empty-tile table.** At 54 MHz a 432-clock line is 3,456 clocks. Per line: tiles 3
   layers x 11 tiles x 32 bytes (66 reads of 16 bytes) and at most 74 sprite rows of 16 bytes; at 10-12 clocks a read,
   1,400-1,700 clocks. Without skipping code-0 sprites it would be 767 rows a line, which does not fit. A 65,536-bit
   table of empty sprite tiles, built while the ROM loads, skips them exactly (an empty tile draws nothing).
3. **Raster.** MAME has no pixel clock or blanking. 6.75 MHz and 432 x 262 is a reading of the driver's sprite budget and
   the 27 MHz crystal, not a measurement. A PCB recording or measurement would settle it.

Memory (MB = 2^20 bytes throughout): `gstream` needs 36.5 MB of SDRAM with its work RAM (32.5 MB of ROM, 4 MB of RAM),
X2222 37 MB (29 MB of ROM regions as laid out for 16-bit pixels, 8 MB of RAM). Neither fits a 32 MB module; the core targets 64 MB and larger (the user's
choice).
