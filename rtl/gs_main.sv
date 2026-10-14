// SPDX-License-Identifier: GPL-3.0-or-later
// The main board (gstream.cpp): E1-32XT CPU, its memory system (gs_cpumem), the backup RAM, the scroll
// registers and the I/O maps of both boards.
//
// I/O space (the port is the CPU's I/O address >> 13, e132xs.cpp 1555; the E1-32X's 13-bit I/O space counts
// dwords, so 0x1000 and 0x1001 are two ports). Unmapped ports read 0.
//   gstream (gstream_io 354-363), 32-bit reads with bits 31:16 zero (MAME's ports, measured):
//     0x1000 R IN0   0x1004 R IN1 (bit 15 is IN0's)   0x1008 R IN2 (IN0/IN1's coin, start and test bits)
//     0x100c W the OKI banks (gstream_oki_banking_w 339-340)    0x1010 W dropped
//     0x1014 RW OKI 1, bits 7:0                                 0x1018 RW OKI 2, bits 7:0
//   X2222 (x2222_io 392-400): 0x1000 R P1, 0x1001 R P2, 0x1002 R SYS, 0x1004 R DSW, 0x100d R IN4 (bit 7 toggles
//     on every read, x2222_toggle_r), 0x100a W dropped (x2222_sound_w); 8-bit ports in bits 7:0
// Scroll registers (scrollx_w / scrolly_w: the value is bits 31:16, written whole when either upper lane is):
//   gstream 0x4f0/0x4f2 layer 2 x/y, 0x4f8/0x4fa layer 0, 0x4fc/0x4fe layer 1 (gstream_32bit_map 278-284)
//   X2222   0x4ff/0x4fe layer 0 x/y, 0x4fd/0x4fc layer 1, 0x4fb/0x4fa layer 2 (x2222_32bit_map 372-379)
// The backup RAM at 0xffc00000 (8 KB): gstream's battery-backed NVRAM (default gstream.nv), X2222's plain RAM.
//
// The vertical blank interrupt is INT1: MAME's irq0_line_hold asserts input line 0 (INPUT_INT1), held until the
// CPU takes it.

module gs_main (
	input             clk,
	input             prst,           // power-up reset of the memory side (not the core reset)
	input             rst,
	input             x2,             // X2222's map
	input             pause,
	input             cpu_tick,       // the CPU's 64 MHz as enables (two in some clocks), for its timer
	input             cpu_tick2,

	input             vblank_irq,     // one clock at the start of the vertical blank
	input      [15:0] in0,            // gstream: IN0, IN1 bits 14:0, active low, as MAME's ports
	input      [15:0] in1,
	input      [7:0]  x_p1,           // X2222: P1, P2, SYS, DSW, IN4 bits 6:0, as MAME's ports
	input      [7:0]  x_p2,
	input      [7:0]  x_sys,
	input      [7:0]  x_dsw,
	input      [6:0]  x_in4,

	// VRAM and palette (gs_video): registered reads
	output            spr_we,
	output     [3:0]  spr_be,
	output     [11:0] spr_addr,
	output     [31:0] spr_wd,
	input      [31:0] spr_rd,
	output            pal_we,
	output     [3:0]  pal_be,
	output     [12:0] pal_addr,
	output     [31:0] pal_wd,
	input      [31:0] pal_rd,
	output reg [15:0] scrollx0, scrolly0, scrollx1, scrolly1, scrollx2, scrolly2,

	// the M6295s (gs_sound)
	output reg [1:0]  oki_wr,
	output reg [7:0]  oki_wd,
	input      [7:0]  oki_dout1,
	input      [7:0]  oki_dout2,
	output reg [1:0]  oki_bank1,
	output reg [1:0]  oki_bank2,

	// the backup RAM: filled with 0 while nv_blank (2048 clocks or more), written by the default image or the
	// .nvm while the CPU is in reset, read back for the save
	input             nv_blank,
	input             nv_load,
	input             nv_load_we,
	input      [12:0] nv_load_addr,
	input      [7:0]  nv_load_data,
	input      [12:0] nv_rd_addr,
	output     [7:0]  nv_rd_data,
	output            nv_written,

	// ROM download writes, and SDRAM port 2
	input             dl_req,
	input      [26:0] dl_addr,
	input      [15:0] dl_data,
	input             dl_we16,
	input             dl_g,
	input      [63:0] dl_gdata,
	output            dl_busy,
	output     [26:1] mem_addr,
	output            mem_wrl,
	output            mem_wrh,
	output     [15:0] mem_din,
	output     [47:0] mem_dinx,
	output      [5:0] mem_wrx,
	output            mem_dbl,
	output            mem_req,
	input             mem_ack,
	input      [63:0] mem_dout,
	input      [63:0] mem_doutb,

	// for the benches
	output            retire,
	output     [31:0] retire_pc,
	output     [31:0] retire_npc,
	output     [31:0] retire_sr,
	output     [31:0] st_imiss,
	output     [31:0] st_dmiss,
	output            dbg_rf_we,
	output     [5:0]  dbg_rf_wa,
	output     [31:0] dbg_rf_wd,

	// architectural trace (rtl/debug/vh_trace.sv)
	input      [23:0] trace_start,
	input      [11:0] trace_idx,
	output            trace_valid,
	output    [187:0] trace_rec,
	output    [187:0] trace_q,
	output     [12:0] trace_count
);

`include "gs_sdram_map.svh"

// ---------------------------------------------------------------- CPU
wire        bus_req, bus_wr, bus_io, bus_ack;
wire        if_req, if_ack;
wire [31:3] if_addr;
wire [63:0] if_data;
wire [31:0] bus_addr, bus_wdata, bus_rdata;
wire [3:0]  bus_be;
wire [6:0]  irq_ack;
reg         int1;

wire        la_req;
wire [31:0] la_addr;
`ifdef E1_CPU
assign la_req = 1'b0;
assign la_addr = 32'd0;
e1_cpu u_cpu (
`else
e1_pipe u_cpu (
	.la_req(la_req), .la_addr(la_addr),
`endif
	.clk(clk), .reset(rst), .cen(1'b1),
	.bus_req(bus_req), .bus_wr(bus_wr), .bus_io(bus_io), .bus_addr(bus_addr),
	.bus_be(bus_be), .bus_wdata(bus_wdata), .bus_ack(bus_ack), .bus_rdata(bus_rdata),
	.if_req(if_req), .if_addr(if_addr), .if_ack(if_ack), .if_data(if_data),
	.irq_in({6'd0, int1}), .irq_ack(irq_ack), .pause(pause), .tick(cpu_tick), .tick2(cpu_tick2),
	.retire(retire), .retire_pc(retire_pc), .retire_npc(retire_npc), .retire_sr(retire_sr),
	.dbg_rf_we(dbg_rf_we), .dbg_rf_wa(dbg_rf_wa), .dbg_rf_wd(dbg_rf_wd)
);

always @(posedge clk) begin
	if (rst) int1 <= 1'b0;
	else if (irq_ack[0]) int1 <= 1'b0;
	else if (vblank_irq) int1 <= 1'b1;
end

vh_trace u_trace (
	.clk(clk), .rst(rst), .start(trace_start),
	.retire(retire), .npc(retire_npc), .sr(retire_sr),
	.rf_we(dbg_rf_we), .rf_wa(dbg_rf_wa), .rf_wd(dbg_rf_wd),
	.bus_req(bus_req), .bus_ack(bus_ack), .bus_wr(bus_wr), .bus_io(bus_io),
	.bus_be(bus_be), .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_rdata(bus_rdata),
	.rec_valid(trace_valid), .rec(trace_rec), .rd_idx(trace_idx), .rd_q(trace_q), .count(trace_count)
);

// ---------------------------------------------------------------- memory
wire        io_rd, io_wr;
wire [18:0] io_port;
wire [31:0] io_wd;
reg  [31:0] io_rdata;
wire        x_we;
wire [3:0]  x_be;
wire [10:0] x_addr;
wire [31:0] x_wd, x_rd;
wire        scr_we;
wire [3:0]  scr_sel;
wire [31:0] scr_wd;

gs_cpumem #(.ROM_BASE(SD_BOOT), .WRAM_BASE(SD_WRAM), .DATA_BASE(SD_DATA), .XRAM_BASE(SD_XRAM)) u_mem (
	.clk(clk), .prst(prst), .rst(rst), .x2(x2), .pal_wait(1'b0),
	.bus_req(bus_req), .bus_wr(bus_wr), .bus_io(bus_io), .bus_addr(bus_addr),
	.bus_be(bus_be), .bus_wdata(bus_wdata), .bus_ack(bus_ack), .bus_rdata(bus_rdata), .la_req(la_req), .la_addr(la_addr),
	.if_req(if_req), .if_addr(if_addr), .if_ack(if_ack), .if_data(if_data),
	.spr_we(spr_we), .spr_be(spr_be), .spr_addr(spr_addr), .spr_wd(spr_wd), .spr_rd(spr_rd),
	.pal_we(pal_we), .pal_be(pal_be), .pal_addr(pal_addr), .pal_wd(pal_wd), .pal_rd(pal_rd),
	.x_we(x_we), .x_be(x_be), .x_addr(x_addr), .x_wd(x_wd), .x_rd(x_rd),
	.scr_we(scr_we), .scr_sel(scr_sel), .scr_wd(scr_wd),
	.io_rd(io_rd), .io_wr(io_wr), .io_port(io_port), .io_wd(io_wd), .io_rdata(io_rdata), .io_late(1'b0),
	.dl_req(dl_req), .dl_addr(dl_addr), .dl_data(dl_data), .dl_we16(dl_we16), .dl_g(dl_g), .dl_gdata(dl_gdata), .dl_busy(dl_busy),
	.mem_addr(mem_addr), .mem_wrl(mem_wrl), .mem_wrh(mem_wrh), .mem_din(mem_din), .mem_dinx(mem_dinx), .mem_wrx(mem_wrx), .mem_dbl(mem_dbl),
	.mem_req(mem_req), .mem_ack(mem_ack), .mem_dout(mem_dout), .mem_doutb(mem_doutb),
	.st_imiss(st_imiss), .st_dmiss(st_dmiss), .dbg_fill_a(), .dbg_fill_d(),
	.dbg_miss(), .dbg_miss_ic(), .dbg_miss_line()
);

// the backup RAM: the CPU on port A, or the blank sweep and the image load while it is in reset; port B reads it
// back. The images hold the bytes in the CPU's order: byte k of a dword is bits 31-8k..24-8k.
wire [31:0] nvq;
wire [3:0]  nv_be = 4'b1000 >> nv_load_addr[1:0];
reg  [10:0] nv_sw;
always @(posedge clk) nv_sw <= nv_blank ? nv_sw + 11'd1 : 11'd0;
vh_dpram #(.AW(11), .DW(32), .NBE(4)) u_nv (
	.clk(clk), .a_ce(1'b1),
	.a_we(nv_blank ? 4'hf : nv_load ? (nv_load_we ? nv_be : 4'd0) : (x_we ? x_be : 4'd0)),
	.a_addr(nv_blank ? nv_sw : nv_load ? nv_load_addr[12:2] : x_addr),
	.a_wd(nv_blank ? 32'd0 : nv_load ? {4{nv_load_data}} : x_wd), .a_rd(x_rd),
	.b_addr(nv_rd_addr[12:2]), .b_rd(nvq)
);
reg [1:0] nv_lane;
always @(posedge clk) nv_lane <= nv_rd_addr[1:0];
assign nv_rd_data = nvq[31 - 8 * nv_lane -: 8];
assign nv_written = x_we;

// ---------------------------------------------------------------- scroll registers
wire scr_be_hi = bus_be[3] || bus_be[2];
always @(posedge clk) begin
	if (rst) begin
		{scrollx0, scrolly0, scrollx1, scrolly1, scrollx2, scrolly2} <= 96'd0;   // machine_reset (823-828)
	end else if (scr_we && scr_be_hi) begin
		if (!x2) case (scr_sel)
			4'h0: scrollx2 <= scr_wd[31:16];
			4'h2: scrolly2 <= scr_wd[31:16];
			4'h8: scrollx0 <= scr_wd[31:16];
			4'ha: scrolly0 <= scr_wd[31:16];
			4'hc: scrollx1 <= scr_wd[31:16];
			4'he: scrolly1 <= scr_wd[31:16];
			default: ;
		endcase else case (scr_sel)
			4'ha: scrolly2 <= scr_wd[31:16];
			4'hb: scrollx2 <= scr_wd[31:16];
			4'hc: scrolly1 <= scr_wd[31:16];
			4'hd: scrollx1 <= scr_wd[31:16];
			4'he: scrolly0 <= scr_wd[31:16];
			4'hf: scrollx0 <= scr_wd[31:16];
			default: ;
		endcase
	end
end

// ---------------------------------------------------------------- I/O
wire [12:0] pk = io_port[12:0];
reg         x_tog;                      // x2222_toggle_r: m_toggle ^= 0xffff, then read: bit 7 of IN4 is the new value
always @* begin
	io_rdata = 32'd0;
	if (!x2) case (pk)
		13'h1000: io_rdata = {16'd0, in0};
		13'h1004: io_rdata = {16'd0, in0[15], in1[14:0]};
		13'h1008: io_rdata = {16'd0, 9'h1ff, in0[15], 2'b11, in1[10], in0[10], in1[9], in0[9]};
		13'h1014: io_rdata = {24'd0, oki_dout1};
		13'h1018: io_rdata = {24'd0, oki_dout2};
		default: ;
	endcase else case (pk)
		13'h1000: io_rdata = {24'd0, x_p1};
		13'h1001: io_rdata = {24'd0, x_p2};
		13'h1002: io_rdata = {24'd0, x_sys};
		13'h1004: io_rdata = {24'd0, x_dsw};
		13'h100d: io_rdata = {24'd0, ~x_tog, x_in4};
		default: ;
	endcase
end

always @(posedge clk) begin
	oki_wr <= 2'b00;
	if (rst) begin
		oki_bank1 <= 2'd0; oki_bank2 <= 2'd0;   // machine_reset (829)
		x_tog <= 1'b0;
	end else begin
		if (io_wr && !x2) begin
			if (pk == 13'h100c) begin
				oki_bank1 <= {io_wd[6] & ~io_wd[7], io_wd[2] & io_wd[3]};
				oki_bank2 <= {io_wd[4] & ~io_wd[5], io_wd[0] & io_wd[1]};
			end
			if (pk == 13'h1014) oki_wr <= 2'b01;
			if (pk == 13'h1018) oki_wr <= 2'b10;
			oki_wd <= io_wd[7:0];
		end
		if (io_rd && x2 && pk == 13'h100d) x_tog <= ~x_tog;
	end
end

endmodule
