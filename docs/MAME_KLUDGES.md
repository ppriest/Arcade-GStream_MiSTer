# MAME kludges this core reproduces

This project follows MAME, including where MAME is wrong (ROADMAP, "Design decisions"), so the
software model and the RTL reproduce MAME's guesses on purpose. This file lists each one that
touches an in-scope set: where it is in MAME, what the core does, and what would settle the real
behaviour.

This core's own approximations are not here; they are in `HACKS.md`.

Source references are to `src/mame/promat/gstream.cpp` unless named. MAME commit: `96962b96c89`.

**Core column:** *copies* MAME; *differs* (and why); *n/a* (not in the core's scope);
*not checked*.

`gstream`: `MACHINE_SUPPORTS_SAVE`. `x2222`: `MACHINE_NO_SOUND`. `x2222o`: `MACHINE_NO_SOUND | MACHINE_IMPERFECT_GRAPHICS`.

## CPU and timing

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| Idle-loop speed-ups | `gstream_speedup_r`, `x2222_speedup_r`, `x2222_speedup2_r` (1058-1087): reads of the idle poll address eat 50 cycles | n/a: they change MAME's speed only | — |
| No raster | `set_refresh_hz(60)`, `set_size(320, 240)`, `set_vblank_time(0)` (844-847): the interrupt and the screen update at the same instant, no blanking | differs: a 432 x 262 raster (`docs/HACKS.md`) | A PCB measurement |
| Data copied to 0x40000000 | "lots of data gets copied here if present, but game runs without it??" (275): gstream leaves the range unmapped | copies: reads 0, writes dropped (`gs_cpumem`) | What the PCB's RAM2 (two KM416C1002) holds |

## Video

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| Sprite budget | "can't be drawable everything": 8 + 128 cycles an entry against `432 * 262`, so entries 0-831 (779-785) | copies (Phase 1) | A PCB capture of a frame with sprites past entry 831 |
| "sprite lag (sprites need buffering?)", "sprite wraparound is imperfect" | 19-20: sprites drawn with the tilemaps from the same VRAM, at four wrap positions | copies (Phase 1). The PCB's four LP621024 SRAMs beside the graphics section could be a sprite frame buffer | A PCB recording of a moving sprite against the background |
| `m_xoffset` | everything drawn 2 pixels left on gstream (1094), 0 on X2222 | copies (Phase 1) | — |
| Sprite colours 28-31 | read past the 0x1c00-entry palette (850; `assert` only, palette.cpp 348) | differs: read the palette RAM's own entries 0x1c00-0x1fff. The game uses colours 0-13 (`HARDWARE_NOTES.md`, census) | — |

## Sound

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| The OKIs' clock and rate | 1 MHz, pin 7 high, "1 Mhz?" (856-858): 7,575.8 Hz samples | copies (`gs_sound`, a 4/243 enable of 60.75 MHz) | A PCB recording: pitch and length of a known sample |
| The bank register | `gstream_oki_banking_w` (300-345): banks derived from observed values ("needs oki1 to be bank 2") | copies (`gs_main`) | The CPLD's equations, or a PCB recording of the music |
| The mix | both chips at gain 1.0, mono (856-858) | copies, then a low-pass (`docs/HACKS.md`) | A PCB recording |

## Inputs

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| X2222's IN4 bit 7 | toggles on every read, "or the game hangs when starting, might be a status flag for the sound?" (218-222) | copies (`gs_main` `x_tog`) | X2222's sound hardware |
