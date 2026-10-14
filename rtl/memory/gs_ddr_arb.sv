// SPDX-License-Identifier: GPL-3.0-or-later
// The DDR3 port (MiSTer DDRAM_*, Avalon-MM: a request is held until a clock without BUSY), shared by
//   ld   the load-time client (the ROM copy's ddram_phy, then the empty-tile scan): owns the port while ld_sel; the
//        others see it busy and the read data is ld's
//   v    the video's graphics reads (gs_video): bursts, the read data is its own
//   r    the HDMI rotator's writes (screen_rotate_two), one beat each
// v and r are granted per request, in turn when both ask. Only v reads in play, so every beat of read data is v's.
// All on clk_sys (DDRAM_CLK).

module gs_ddr_arb (
	input             clk,
	input             ld_sel,

	input       [7:0] ld_burst,
	input      [28:0] ld_addr,
	input      [63:0] ld_din,
	input       [7:0] ld_be,
	input             ld_we,
	input             ld_rd,
	output            ld_busy,
	output            ld_dv,

	input             v_rd,
	input      [28:0] v_addr,
	input       [7:0] v_burst,
	output            v_busy,
	output            v_dv,

	input       [7:0] r_burst,
	input      [28:0] r_addr,
	input      [63:0] r_din,
	input       [7:0] r_be,
	input             r_we,
	output            r_busy,

	input             DDRAM_BUSY,
	output      [7:0] DDRAM_BURSTCNT,
	output     [28:0] DDRAM_ADDR,
	output     [63:0] DDRAM_DIN,
	output      [7:0] DDRAM_BE,
	output            DDRAM_WE,
	output            DDRAM_RD,
	input             DDRAM_DOUT_READY
);

reg  last_v = 1'b0;                            // the last request granted in play was v's
wire want_v = v_rd, want_r = r_we;
wire give_v = want_v && (!want_r || !last_v);
wire give_r = want_r && !give_v;
always @(posedge clk) if (!ld_sel && !DDRAM_BUSY && (give_v || give_r)) last_v <= give_v;

assign DDRAM_BURSTCNT = ld_sel ? ld_burst : give_r ? r_burst : v_burst;
assign DDRAM_ADDR     = ld_sel ? ld_addr  : give_r ? r_addr  : v_addr;
assign DDRAM_DIN      = ld_sel ? ld_din   : r_din;
assign DDRAM_BE       = ld_sel ? ld_be    : give_r ? r_be : 8'hff;
assign DDRAM_WE       = ld_sel ? ld_we    : give_r;
assign DDRAM_RD       = ld_sel ? ld_rd    : give_v;

assign ld_busy = DDRAM_BUSY | !ld_sel;
assign v_busy  = DDRAM_BUSY | ld_sel | !give_v;
assign r_busy  = DDRAM_BUSY | ld_sel | !give_r;
assign ld_dv   = DDRAM_DOUT_READY & ld_sel;
assign v_dv    = DDRAM_DOUT_READY & !ld_sel;

endmodule
