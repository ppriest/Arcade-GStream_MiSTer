// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone synthesis wrapper for the main board (gs_main: the E1, the memory unit, the backup RAM, the I/O):
// every port straight to a virtual pin (gs_synth.qsf), so area and Fmax are the board's own. The trace buffer is
// left unconnected and removed, as in the release build.
module gs_synth_top (
	input clk, input prst, input rst, input x2, input pause, input cpu_tick, input cpu_tick2, input vblank_irq,
	input [15:0] in0, input [15:0] in1, input [7:0] x_p1, input [7:0] x_p2, input [7:0] x_sys, input [7:0] x_dsw,
	input [6:0] x_in4,
	output spr_we, output [3:0] spr_be, output [11:0] spr_addr, output [31:0] spr_wd, input [31:0] spr_rd,
	output pal_we, output [3:0] pal_be, output [12:0] pal_addr, output [31:0] pal_wd, input [31:0] pal_rd,
	output [15:0] scrollx0, output [15:0] scrolly0, output [15:0] scrollx1, output [15:0] scrolly1,
	output [15:0] scrollx2, output [15:0] scrolly2,
	output [1:0] oki_wr, output [7:0] oki_wd, input [7:0] oki_dout1, input [7:0] oki_dout2,
	output [1:0] oki_bank1, output [1:0] oki_bank2,
	input nv_blank, input nv_load, input nv_load_we, input [12:0] nv_load_addr, input [7:0] nv_load_data,
	input [12:0] nv_rd_addr, output [7:0] nv_rd_data, output nv_written,
	input dl_req, input [26:0] dl_addr, input [15:0] dl_data, input dl_we16, input dl_g, input [63:0] dl_gdata,
	output dl_busy,
	output [26:1] mem_addr, output mem_wrl, output mem_wrh, output [15:0] mem_din, output [47:0] mem_dinx,
	output [5:0] mem_wrx, output mem_dbl, output mem_req, input mem_ack, input [63:0] mem_dout, input [63:0] mem_doutb
);
gs_main u_main (
	.retire(), .retire_pc(), .retire_npc(), .retire_sr(), .st_imiss(), .st_dmiss(), .dbg_rf_we(), .dbg_rf_wa(),
	.dbg_rf_wd(), .trace_start(24'hffffff), .trace_idx(12'd0), .trace_valid(), .trace_rec(), .trace_q(), .trace_count(),
	.*
);
endmodule
