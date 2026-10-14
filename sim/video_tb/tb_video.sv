// SPDX-License-Identifier: GPL-3.0-or-later
// Video bench top: gs_video alone; main.cpp writes VRAM and palette through the CPU ports, sets the scroll registers,
// fills the empty table and answers the DDR3 port from the download image.
module tb_video (
	input             clk,
	input             rst,
	input             spr_we,
	input      [3:0]  spr_be,
	input      [11:0] spr_addr,
	input      [31:0] spr_wd,
	input             pal_we,
	input      [3:0]  pal_be,
	input      [12:0] pal_addr,
	input      [31:0] pal_wd,
	input      [15:0] scrollx0, scrolly0, scrollx1, scrolly1, scrollx2, scrolly2,
	input             flip,
	input             et_we,
	input      [12:0] et_addr,
	input      [7:0]  et_data,
	output            gfx_rd,
	output     [27:3] gfx_addr,
	output     [7:0]  gfx_burst,
	input             gfx_busy,
	input             gfx_dv,
	input      [63:0] gfx_dout,
	output            ce_pix,
	output            hblank,
	output            vblank,
	output            vblank_irq,
	output     [7:0]  r,
	output     [7:0]  g,
	output     [7:0]  b,
	output     [15:0] dbg_overrun,
	output     [11:0] dbg_maxbusy
);
gs_video u_video (
	.clk(clk), .rst(rst),
	.spr_we(spr_we), .spr_be(spr_be), .spr_addr(spr_addr), .spr_wd(spr_wd), .spr_rd(),
	.pal_we(pal_we), .pal_be(pal_be), .pal_addr(pal_addr), .pal_wd(pal_wd), .pal_rd(),
	.scrollx0(scrollx0), .scrolly0(scrolly0), .scrollx1(scrollx1), .scrolly1(scrolly1), .scrollx2(scrollx2), .scrolly2(scrolly2), .flip(flip),
	.et_we(et_we), .et_addr(et_addr), .et_data(et_data),
	.gfx_rd(gfx_rd), .gfx_addr(gfx_addr), .gfx_burst(gfx_burst), .gfx_busy(gfx_busy), .gfx_dv(gfx_dv), .gfx_dout(gfx_dout),
	.ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(), .vsync(), .vblank_irq(vblank_irq),
	.r(r), .g(g), .b(b), .dbg_overrun(dbg_overrun), .dbg_maxbusy(dbg_maxbusy)
);
endmodule
