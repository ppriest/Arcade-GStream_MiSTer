// SPDX-License-Identifier: GPL-3.0-or-later
// The download image's layout, byte offsets, in DDR3 from 0x30000000 (where the HPS puts it) and, below SD_SDRAM_END,
// in SDRAM (vh_rom_loader copies that part); the graphics are read from DDR3 during play (docs/ROADMAP.md, Memory
// plan). scripts/build_mra.py reads the SD_* localparams from this file, so the two cannot drift. The RAMs are SDRAM
// only, at addresses the image's graphics occupy in DDR3.
//   SD_BOOT   1 MB   the boot ROM's window 0xfff00000-0xffffffff: gstream's 512 KB at +0x80000 (0xfff80000),
//                    x2222's 1 MB, x2222o's 512 KB at +0x80000 (ROM_LOAD at 0x080000)
//   SD_DATA   2 MB   gstream's "maindata", the CPU's byte order (ROM_REGION32_BE, ROM_LOAD16_WORD_SWAP)
//   SD_OKI1/2 1 MB   gstream's "oki1" and "oki2"
//   SD_SPR    16 MB  sprite tiles: gstream's "gfx1" as MAME's region; X2222's 16-bit pixels (init_x2222)
//   SD_TILE0  4 MB   tile layer 0 (gstream "gfx2"), then layers 1 and 2 ("gfx3", "gfx4"); X2222: 16-bit pixels
//   SD_WRAM   4 MB   work RAM at 0
//   SD_XRAM   4 MB   X2222's RAM at 0x40000000
localparam [26:0] SD_BOOT      = 27'h0000000;
localparam [26:0] SD_DATA      = 27'h0100000;
localparam [26:0] SD_OKI1      = 27'h0300000;
localparam [26:0] SD_OKI2      = 27'h0400000;
localparam [26:0] SD_SPR       = 27'h0500000;
localparam [26:0] SD_TILE0     = 27'h1500000;
localparam [26:0] SD_TILE1     = 27'h1900000;
localparam [26:0] SD_TILE2     = 27'h1d00000;
localparam [26:0] SD_IMAGE_END = 27'h2100000;
localparam [26:0] SD_SDRAM_END = 27'h0500000;
localparam [26:0] SD_WRAM      = 27'h0800000;
localparam [26:0] SD_XRAM      = 27'h0c00000;
