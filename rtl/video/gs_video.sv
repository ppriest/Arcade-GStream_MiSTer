// SPDX-License-Identifier: GPL-3.0-or-later
// gstream video (gstream.cpp screen_update 750): three 512x512 tilemaps of 32x32 8bpp tiles and up to
// 832 16x16 8bpp sprites, drawn per scanline; graphics come from DDR3.
//
// CPU memory, 32-bit words:
//   VRAM 0x80000000-0x80003fff: tilemap entries in bits 31:16 (layer n at dword n*0x100), sprite list in
//     bits 15:0 (entry i at dwords 4i..4i+3: code, x, y, colour)
//   palette 0x4f400000-0x4f406fff: two BGR565 entries a dword, even in bits 31:16
// VRAM is read live after the vblank interrupt; sprite fields are shadowed in four RAMs, one per field.
// The palette is read live and scroll registers are latched per line.
//
// Raster: ce_pix 1 in 9 (6.75 MHz), 432x262, visible 320x240 from (0,0) (docs/HACKS.md: MAME has no raster).
// Line v draws line v+1: tiles for 3 layers and 11 columns, then 832 sprite entries; DDR3 reads are
// queued up to MAXQ bursts. Scan-out mixes sprite, layer 0-2, else black.
// Colours: sprite col*256+pen, layer n 0x1000+0x400*n+pal*256+pen (gfx_gstream 555).
// Flip (OSD only; the board has none) turns the picture 180 degrees and is latched at vblank.

module gs_video #(
	parameter [27:0] SPR_BASE  = 28'h0500000,    // SD_SPR, a byte offset in the DDR3 image
	parameter [27:0] TILE_BASE = 28'h1500000,    // SD_TILE0; layers 1 and 2 follow at 4 MB steps
	parameter [3:0]  MAXQ      = 4'd6
) (
	input             clk,
	input             rst,

	// CPU side (gs_main): registered reads
	input             spr_we,
	input      [3:0]  spr_be,
	input      [11:0] spr_addr,
	input      [31:0] spr_wd,
	output     [31:0] spr_rd,
	input             pal_we,
	input      [3:0]  pal_be,
	input      [12:0] pal_addr,
	input      [31:0] pal_wd,
	output     [31:0] pal_rd,
	input      [15:0] scrollx0, scrolly0, scrollx1, scrolly1, scrollx2, scrolly2,
	input             flip,

	// the empty-sprite-tile table: bit k of byte a is tile 8a + k, 1 = all pixels zero (written at load)
	input             et_we,
	input      [12:0] et_addr,
	input      [7:0]  et_data,

	// graphics in DDR3 (an Avalon-style read port: a burst is accepted in a clock with gfx_rd and !gfx_busy)
	output reg        gfx_rd = 1'b0,
	output reg [27:3] gfx_addr,          // byte offset in the image, 8-byte aligned
	output reg [7:0]  gfx_burst,
	input             gfx_busy,
	input             gfx_dv,
	input      [63:0] gfx_dout,          // byte i of the beat in [8i+7:8i]

	output reg        ce_pix = 1'b0,
	output reg        hblank = 1'b1,
	output reg        vblank = 1'b1,
	output reg        hsync = 1'b0,
	output reg        vsync = 1'b0,
	output reg        vblank_irq = 1'b0,
	output reg [7:0]  r = 8'd0,
	output reg [7:0]  g = 8'd0,
	output reg [7:0]  b = 8'd0,

	output reg [15:0] dbg_overrun = 16'd0,     // lines whose pass was still running when the next began
	output reg [11:0] dbg_maxbusy = 12'd0      // longest pass, clocks
);

localparam [1:0] XOFF = 2'd2;                  // m_xoffset (init_gstream, 1094)

//------------------------------------------------------------------
// raster
//------------------------------------------------------------------
reg [3:0] pc = 4'd0;
reg [8:0] hc = 9'd0, vc = 9'd0;
wire      last_pc = pc == 4'd8;
wire      line_start = pc == 4'd0 && hc == 9'd0;
always @(posedge clk) begin
	vblank_irq <= 1'b0;
	if (rst) begin
		pc <= 4'd0; hc <= 9'd0; vc <= 9'd0;
	end else begin
		pc <= last_pc ? 4'd0 : pc + 4'd1;
		if (last_pc) begin
			if (hc == 9'd431) begin
				hc <= 9'd0;
				vc <= vc == 9'd261 ? 9'd0 : vc + 9'd1;
				if (vc == 9'd239) vblank_irq <= 1'b1;
			end else hc <= hc + 9'd1;
		end
	end
end

//------------------------------------------------------------------
// RAMs: VRAM (CPU / tile pass), the sprite fields, the empty table, the palette (CPU / scan-out)
//------------------------------------------------------------------
reg  [11:0] vr_addr;
wire [31:0] vr_q;
vh_dpram #(.AW(12), .DW(32), .NBE(4)) u_vram (
	.clk(clk), .a_ce(1'b1), .a_we(spr_we ? spr_be : 4'd0), .a_addr(spr_addr), .a_wd(spr_wd), .a_rd(spr_rd),
	.b_addr(vr_addr), .b_rd(vr_q)
);

reg  [9:0]  sc_e = 10'd0;
wire [15:0] f_q [0:3];
genvar fk;
generate for (fk = 0; fk < 4; fk = fk + 1) begin : field
	gs_sdp_be #(.AW(10)) u_f (
		.clk(clk), .we(spr_we && spr_addr[1:0] == fk ? spr_be[1:0] : 2'b00), .wa(spr_addr[11:2]), .wd(spr_wd[15:0]),
		.ra(sc_e), .rd(f_q[fk])
	);
end endgenerate

// read with the code the fields hand out, so the bit arrives with the hit's next stage
reg  [7:0]  et_q;
reg  [7:0]  et_mem [0:8191];
always @(posedge clk) begin
	if (et_we) et_mem[et_addr] <= et_data;
	et_q <= et_mem[f_q[0][15:3]];
end

reg  [12:0] pv_addr;
wire [31:0] pv_q;
vh_dpram #(.AW(13), .DW(32), .NBE(4)) u_pal (
	.clk(clk), .a_ce(1'b1), .a_we(pal_we ? pal_be : 4'd0), .a_addr(pal_addr), .a_wd(pal_wd), .a_rd(pal_rd),
	.b_addr(pv_addr), .b_rd(pv_q)
);

//------------------------------------------------------------------
// line engine
//------------------------------------------------------------------
wire [8:0] tline = vc == 9'd261 ? 9'd0 : vc + 9'd1;
wire       t_active = tline < 9'd240;
reg        flip_l = 1'b0;
always @(posedge clk) if (line_start && vc == 9'd240) flip_l <= flip;

reg        eng_run = 1'b0;
reg        eng_b = 1'b0;                       // the buffer being drawn: the target line's bit 0
reg  [8:0] eng_t;
reg [11:0] busy_cnt;
// scroll for the line being drawn, and per buffer for its scan-out
reg  [8:0] lsx [0:2], lsy [0:2];
reg  [8:0] bsx [0:1][0:2];

// tile pass: 33 entries, layer-major. The address is registered (t), the RAM takes it (t+1), the entry is there (t+2)
reg        tp_run;
reg  [1:0] tp_n;
reg  [3:0] tp_k;
reg        tp_v1, tp_v2;
reg [10:0] tq1, tq2;                           // n 2, tx 4, r 5 of the entry in flight
wire [8:0] my_n = eng_t + lsy[tp_n];
wire [8:0] mx_n = lsx[tp_n] + {7'd0, XOFF};
wire [3:0] tx_n = mx_n[8:5] + tp_k;

// sprite scan: the fields of entry sc_e arrive the clock after (s1), the empty bit with the hit (s2)
reg        sc_run;
reg        s1_v, s2_v;
reg [15:0] s2_code;
reg  [3:0] s2_row;
reg  [8:0] s2_x;
reg  [4:0] s2_col;

// request queue, DDR3 bursts not yet issued:
//   sprite {1, code 16, row 4, x 9, col 5}   tile {0, 8'd0, n 2, tx 4, r 5, code 12, pal 2}
localparam QW = 35, QD = 16;
(* ramstyle = "logic" *) reg [QW-1:0] rq [0:QD-1];
reg  [4:0] rq_wr, rq_rd;
wire [4:0] rq_cnt = rq_wr - rq_rd;
// bursts issued, in issue order (the data comes back in that order)
(* ramstyle = "logic" *) reg [QW-1:0] fq [0:7];
reg  [3:0] fq_wr = 4'd0, fq_rd = 4'd0;
wire [3:0] fq_cnt = fq_wr - fq_rd;
reg  [1:0] beat = 2'd0;
// sprite rows waiting to be drawn. A row takes 16 clocks to draw and 2 beats to fetch, so a sprite burst is issued
// only while the rows in flight and those queued leave it a place (sp_fly + dq_cnt < 8)
(* ramstyle = "logic" *) reg [127:0] dq_row [0:7];
(* ramstyle = "logic" *) reg [13:0]  dq_meta [0:7];     // x 9, col 5
reg  [3:0] dq_wr, dq_rd;
wire [3:0] dq_cnt = dq_wr - dq_rd;
reg  [3:0] sp_fly = 4'd0;                      // sprite bursts issued whose row has not reached dq
reg [63:0] s_lo;
// draw
reg        d_busy;
reg  [3:0] d_i;
reg [127:0] d_row;
reg  [8:0] d_x;
reg  [4:0] d_col;

// line buffers. Tiles: one per layer, two buffers each, 64 words of 8 pixels {pal 2, pen 8}, in map columns.
// Sprites: two buffers of 512 x {col 5, pen 8}, cleared as they are scanned out.
reg        tw_we;
reg  [1:0] tw_n;
reg  [5:0] tw_a;
reg [79:0] tw_d;
reg  [5:0] tr_a [0:2];
wire [79:0] tr_q [0:2][0:1];
genvar ln, lb;
generate for (ln = 0; ln < 3; ln = ln + 1) begin : tlb
	for (lb = 0; lb < 2; lb = lb + 1) begin : bf
		gs_sdp #(.AW(6), .DW(80)) u_t (
			.clk(clk), .we(tw_we && tw_n == ln && eng_b == lb), .wa(tw_a), .wd(tw_d), .ra(tr_a[ln]), .rd(tr_q[ln][lb])
		);
	end
end endgenerate

reg        sw_we;
reg  [8:0] sw_a;
reg [12:0] sw_d;
reg        so_we;                              // scan-out's clear
reg  [8:0] so_a;
wire [12:0] so_q [0:1];
generate for (lb = 0; lb < 2; lb = lb + 1) begin : slb
	gs_tdp #(.AW(9), .DW(13)) u_s (
		.clk(clk),
		.a_we(sw_we && eng_b == lb), .a_addr(sw_a), .a_wd(sw_d),
		.b_we(so_we && vc[0] == lb), .b_addr(so_a), .b_wd(13'd0), .b_rd(so_q[lb])
	);
end endgenerate

wire [15:0] te    = vr_q[31:16];
wire [7:0]  srow  = eng_t[7:0] - f_q[2][7:0];
wire        shit  = s1_v && srow[7:4] == 4'd0;
wire [7:0]  d_pen = d_row[8 * d_i +: 8];
wire [8:0]  d_xs  = d_x + {5'd0, d_i} - {7'd0, XOFF};
wire [QW-1:0] rq_head = rq[rq_rd[3:0]];
wire [QW-1:0] fq_head = fq[fq_rd[2:0]];
wire        fq_spr = fq_head[QW-1];
wire        issue = (!gfx_rd || !gfx_busy) && rq_cnt != 5'd0 && fq_cnt < MAXQ &&
                    (!rq_head[QW-1] || sp_fly + dq_cnt < 4'd8);
wire        sp_in = gfx_dv && fq_cnt != 4'd0 && fq_spr && beat == 2'd1;   // a sprite row completes

integer q;
always @(posedge clk) begin
	tw_we <= 1'b0;
	sw_we <= 1'b0;
	if (gfx_rd && !gfx_busy) gfx_rd <= 1'b0;   // accepted
	sp_fly <= sp_fly + {3'd0, eng_run && !line_start && !rst && issue && rq_head[QW-1]} - {3'd0, sp_in};
	// data: in issue order, whatever pass is running; a burst of an aborted pass is drained and dropped
	if (gfx_dv && fq_cnt != 4'd0) begin
		beat <= beat + 2'd1;
		if (beat == (fq_spr ? 2'd1 : 2'd3)) begin beat <= 2'd0; fq_rd <= fq_rd + 4'd1; end
	end
	if (rst) begin
		eng_run <= 1'b0; tp_run <= 1'b0; sc_run <= 1'b0; tp_v1 <= 1'b0; tp_v2 <= 1'b0; s1_v <= 1'b0; s2_v <= 1'b0;
		rq_wr <= 5'd0; rq_rd <= 5'd0; dq_wr <= 4'd0; dq_rd <= 4'd0; d_busy <= 1'b0; busy_cnt <= 12'd0;
	end else if (line_start) begin
		if (eng_run) dbg_overrun <= dbg_overrun + 16'd1;
		busy_cnt <= 12'd0;
		eng_run <= t_active;
		eng_t <= flip_l ? 9'd239 - tline : tline; eng_b <= tline[0];
		tp_run <= t_active; tp_n <= 2'd0; tp_k <= 4'd0; tp_v1 <= 1'b0; tp_v2 <= 1'b0;
		sc_run <= t_active; sc_e <= 10'd0; s1_v <= 1'b0; s2_v <= 1'b0;
		rq_wr <= 5'd0; rq_rd <= 5'd0; dq_wr <= 4'd0; dq_rd <= 4'd0; d_busy <= 1'b0;
		lsx[0] <= scrollx0[8:0]; lsy[0] <= scrolly0[8:0];
		lsx[1] <= scrollx1[8:0]; lsy[1] <= scrolly1[8:0];
		lsx[2] <= scrollx2[8:0]; lsy[2] <= scrolly2[8:0];
		bsx[tline[0]][0] <= scrollx0[8:0]; bsx[tline[0]][1] <= scrollx1[8:0]; bsx[tline[0]][2] <= scrollx2[8:0];
	end else if (eng_run) begin
		if (busy_cnt != 12'hfff) busy_cnt <= busy_cnt + 12'd1;

		// tile pass, while the queue has room for what is in the pipeline
		tp_v1 <= 1'b0;
		tp_v2 <= tp_v1; tq2 <= tq1;
		if (tp_run && rq_cnt < QD - 4) begin
			vr_addr <= {2'b00, tp_n, my_n[8:5], tx_n};
			tq1 <= {tp_n, tx_n, my_n[4:0]};
			tp_v1 <= 1'b1;
			if (tp_k == 4'd10) begin
				tp_k <= 4'd0;
				if (tp_n == 2'd2) tp_run <= 1'b0; else tp_n <= tp_n + 2'd1;
			end else tp_k <= tp_k + 4'd1;
		end
		// sprite scan, once the tiles' entries are queued
		s1_v <= 1'b0;
		s2_v <= 1'b0;
		if (!tp_run && !tp_v1 && !tp_v2 && sc_run && rq_cnt < QD - 4) begin
			s1_v <= 1'b1;
			if (sc_e == 10'd831) sc_run <= 1'b0; else sc_e <= sc_e + 10'd1;
		end
		if (shit) begin
			s2_v <= 1'b1;
			s2_code <= f_q[0]; s2_row <= srow[3:0]; s2_x <= f_q[1][8:0]; s2_col <= f_q[3][4:0];
		end
		// the queue: a tile entry and a sprite hit never arrive in the same clock
		if (tp_v2) begin
			rq[rq_wr[3:0]] <= {1'b0, 8'd0, tq2, te[11:0], te[15:14]};
			rq_wr <= rq_wr + 5'd1;
		end else if (s2_v && !et_q[s2_code[2:0]]) begin
			rq[rq_wr[3:0]] <= {1'b1, s2_code, s2_row, s2_x, s2_col};
			rq_wr <= rq_wr + 5'd1;
		end

		// issue one burst a clock while fewer than MAXQ are in flight
		if (issue) begin
			gfx_rd <= 1'b1;
			if (rq_head[QW-1]) begin
				gfx_addr <= (SPR_BASE + {4'd0, rq_head[33:18], 8'd0} + {20'd0, rq_head[17:14], 4'd0}) >> 3;
				gfx_burst <= 8'd2;
			end else begin
				gfx_addr <= (TILE_BASE + {4'd0, rq_head[24:23], 22'd0} + {6'd0, rq_head[13:2], 10'd0} +
				             {18'd0, rq_head[18:14], 5'd0}) >> 3;
				gfx_burst <= 8'd4;
			end
			fq[fq_wr[2:0]] <= rq_head;
			fq_wr <= fq_wr + 4'd1;
			rq_rd <= rq_rd + 5'd1;
		end

		// data
		if (gfx_dv && fq_cnt != 4'd0) begin
			if (!fq_spr) begin                            // tile: 8 pixels a beat into the layer's buffer
				tw_we <= 1'b1;
				tw_n <= fq_head[24:23];
				tw_a <= {fq_head[22:19], beat};
				for (q = 0; q < 8; q = q + 1) tw_d[10 * q +: 10] <= {fq_head[1:0], gfx_dout[8 * q +: 8]};
			end else if (beat == 2'd0) s_lo <= gfx_dout;  // sprite: two beats make the row
			else begin
				dq_row[dq_wr[2:0]] <= {gfx_dout, s_lo};
				dq_meta[dq_wr[2:0]] <= fq_head[13:0];
				dq_wr <= dq_wr + 4'd1;
			end
		end

		// draw: one pixel a clock
		if (!d_busy && dq_cnt != 4'd0) begin
			d_row <= dq_row[dq_rd[2:0]];
			{d_x, d_col} <= dq_meta[dq_rd[2:0]];
			d_i <= 4'd0; d_busy <= 1'b1;
			dq_rd <= dq_rd + 4'd1;
		end
		if (d_busy) begin
			sw_we <= d_pen != 8'd0;
			sw_a <= d_xs;
			sw_d <= {d_col, d_pen};
			d_i <= d_i + 4'd1;
			if (d_i == 4'd15) d_busy <= 1'b0;
		end

		if (!tp_run && !tp_v1 && !tp_v2 && !sc_run && !s1_v && !s2_v && rq_cnt == 5'd0 && fq_cnt == 4'd0 && !gfx_rd &&
		    dq_cnt == 4'd0 && !d_busy) begin
			eng_run <= 1'b0;
			if (busy_cnt > dbg_maxbusy) dbg_maxbusy <= busy_cnt;
		end
	end
end

//------------------------------------------------------------------
// scan-out. For the pixel at hc, from pc 0:
//   0  line buffer addresses     2  data: the colour chosen, palette address, the sprite entry cleared
//   4  palette data              5  outputs
//------------------------------------------------------------------
wire       x_act = hc < 9'd320;
wire       y_act = vc < 9'd240;
wire [8:0] sx  = flip_l ? 9'd319 - hc : hc;           // the unflipped column shown at hc
wire [8:0] mc0 = sx + {7'd0, XOFF} + bsx[vc[0]][0];
wire [8:0] mc1 = sx + {7'd0, XOFF} + bsx[vc[0]][1];
wire [8:0] mc2 = sx + {7'd0, XOFF} + bsx[vc[0]][2];
reg  [2:0] mcl0, mcl1, mcl2;
reg        act1;
reg        pv_lsb;
reg        opaque;
reg        sb;                                 // the buffer scanned out: this line's bit 0
wire [9:0] tp0 = tr_q[0][sb][10 * mcl0 +: 10];
wire [9:0] tp1 = tr_q[1][sb][10 * mcl1 +: 10];
wire [9:0] tp2 = tr_q[2][sb][10 * mcl2 +: 10];
wire [12:0] sp = so_q[sb];
wire [15:0] ent = pv_lsb ? pv_q[15:0] : pv_q[31:16];

always @(posedge clk) begin
	so_we <= 1'b0;
	if (pc == 4'd0) begin
		tr_a[0] <= mc0[8:3]; tr_a[1] <= mc1[8:3]; tr_a[2] <= mc2[8:3];
		mcl0 <= mc0[2:0]; mcl1 <= mc1[2:0]; mcl2 <= mc2[2:0];
		so_a <= sx;
		sb <= vc[0];
		act1 <= x_act && y_act;
	end
	if (pc == 4'd2) begin
		// sprite, then layer 0, 1, 2; the colour index is 13 bits, two entries a palette dword
		opaque <= act1 && (sp[7:0] != 8'd0 || tp0[7:0] != 8'd0 || tp1[7:0] != 8'd0 || tp2[7:0] != 8'd0);
		{pv_addr, pv_lsb} <= sp[7:0]  != 8'd0 ? {1'b0, sp} :
		                     tp0[7:0] != 8'd0 ? {4'b0100, tp0} :
		                     tp1[7:0] != 8'd0 ? {4'b0101, tp1} :
		                                        {4'b0110, tp2};
		so_we <= act1;                         // clear the sprite entry after its read
	end
	if (pc == 4'd5) begin
		if (opaque) begin
			r <= {ent[4:0], ent[4:2]};
			g <= {ent[10:5], ent[10:9]};
			b <= {ent[15:11], ent[15:13]};
		end else begin
			r <= 8'd0; g <= 8'd0; b <= 8'd0;
		end
		hblank <= !x_act;
		vblank <= !y_act;
		hsync  <= hc >= 9'd336 && hc < 9'd368;
		vsync  <= vc >= 9'd244 && vc < 9'd247;
	end
	ce_pix <= pc == 4'd5;
end

endmodule


// simple dual-port RAM, one write port and one read port, registered read
module gs_sdp #(parameter AW = 6, parameter DW = 80) (
	input             clk,
	input             we,
	input      [AW-1:0] wa,
	input      [DW-1:0] wd,
	input      [AW-1:0] ra,
	output reg [DW-1:0] rd
);
reg [DW-1:0] mem [0:(1<<AW)-1];
always @(posedge clk) if (we) mem[wa] <= wd;
always @(posedge clk) rd <= mem[ra];
endmodule

// simple dual-port RAM, 16 bits with two byte enables
module gs_sdp_be #(parameter AW = 10) (
	input             clk,
	input      [1:0]  we,
	input      [AW-1:0] wa,
	input      [15:0] wd,
	input      [AW-1:0] ra,
	output reg [15:0] rd
);
reg [15:0] mem [0:(1<<AW)-1];
always @(posedge clk) begin
	if (we[0]) mem[wa][7:0] <= wd[7:0];
	if (we[1]) mem[wa][15:8] <= wd[15:8];
	rd <= mem[ra];
end
endmodule

// true dual-port: A writes, B reads and writes
module gs_tdp #(parameter AW = 9, parameter DW = 13) (
	input             clk,
	input             a_we,
	input      [AW-1:0] a_addr,
	input      [DW-1:0] a_wd,
	input             b_we,
	input      [AW-1:0] b_addr,
	input      [DW-1:0] b_wd,
	output reg [DW-1:0] b_rd
);
(* ramstyle = "M10K, no_rw_check" *) reg [DW-1:0] mem [0:(1<<AW)-1];
always @(posedge clk) if (a_we) mem[a_addr] <= a_wd;
always @(posedge clk) begin
	if (b_we) mem[b_addr] <= b_wd;
	b_rd <= mem[b_addr];
end
endmodule
