# GStream state inventory

What a savestate or a state dump has to carry, kept current as RTL lands (the skill's
`savestates.md`). "Skip" needs a reason: a ROM table from the `.mra`, or something re-derived
every frame.

## RAMs

| Region | RTL | Width x depth | Bytes | Save? |
|---|---|---|---|---|
| Work RAM | SDRAM `SD_WRAM` (through `gs_cpumem`'s caches, written through) | 16 x 2M | 4 MB | yes |
| X2222's RAM at 0x40000000 | SDRAM `SD_XRAM` | 16 x 2M | 4 MB | yes (X2222) |
| E1 internal RAM | `gs_cpumem` `u_iram` | 64 x 1024 | 8 KB | yes |
| Backup RAM | `gs_main` `u_nv` (port B free) | 32 x 2048 | 8 KB | yes |
| VRAM | `gs_video` `u_vram` (port B the renderer's) | 32 x 4096 | 16 KB | yes |
| Palette | `gs_video` `u_pal` (port B the renderer's) | 32 x 8192 (7168 used) | 28 KB | yes |
| I- and D-cache | `gs_cpumem` `u_ic`, `u_dc` | | 20 KB | skip: write-through, re-filled after an invalidation |
| Sprite field shadows x 4 | `gs_video` `field[k].u_f` | 16 x 1024 each | 8 KB | skip: rebuilt from the VRAM (written with it) |
| Empty-sprite-tile table | `gs_video` `et_mem` | 8 x 8192 | 8 KB | skip: built from the ROM at load |
| Line buffers: 3 tile layers, sprites | `gs_video` `tlb`, `slb` | | | skip: redrawn every line |

## Registers and FSMs

| What | RTL | Bits | Save? | MAME `save_item` equivalent |
|---|---|---|---|---|
| Scroll registers x 6 | `gs_main` `scrollx0`..`scrolly2` | 6 x 16 | yes | `m_scrollx`, `m_scrolly` |
| OKI banks | `gs_main` `oki_bank1`, `oki_bank2` | 2 x 2 | yes | `m_oki_bank` |
| Held vblank interrupt | `gs_main` `int1` | 1 | yes | the CPU's input line state |
| X2222's IN4 toggle | `gs_main` `x_tog` | 1 | yes | `m_toggle` (not saved by MAME) |
| E1 registers, pipeline, write queue | `e1_pipe` | | yes | the CPU's state |
| Raster counters | `gs_video` `hc`, `vc` | 18 | yes | the screen's position |

## Chip state

| Chip | Module | Addressable? | Tier | Note |
|---|---|---|---|---|
| M6295 x 2 | `jt6295` in `gs_sound` | no: registers inside jotego's module | to decide | the sample caches are re-filled |

## Deliberately skipped

| What | Why it need not be saved |
|---|---|
| | |

## Frame alignment

Restore point (normally `frame_start`), and anything whose phase must be saved with it: sprite or
tile double-buffer selection, snapshot ownership bits.
