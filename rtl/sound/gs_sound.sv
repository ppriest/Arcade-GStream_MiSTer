// SPDX-License-Identifier: GPL-3.0-or-later
// gstream's sound (gstream.cpp 856-858): two OKI M6295s (AD-65) on 1 MHz, pin 7 high, mixed mono at gain
// 1.0 each. Each chip addresses 256 KB of its 1 MB region through the bank gs_main latches from I/O 0x100c
// (gstream_oki_banking_w, 339-345). jt6295 unchanged; each chip's ROM is read from SDRAM through Vamphalf's
// bridge and granule cache (rtl/sound/PROVENANCE.md), as Arcade-Eolith_MiSTer's eo_oki.sv; the two caches
// share one SDRAM port, granule requests served in turn.
//
// The enable is exact: 1 MHz is 4/243 of 60.75 MHz, a pulse when an accumulator stepping by 4 wraps at 243.
// jt6295's sum is 14 bits with one voice at 12; each chip is scaled by 16 (as eo_oki), then added and clipped.
//
// Checks (GStream_stp's probe S, sim/sys_tb): dbg_late counts the ADPCM bytes jt6295 took before the bridge had them
// (jt6295_rom latches the byte on the last clock of its st == 2 slot and does not wait; a replica of its timing,
// which has no reset, runs in step); dbg_maxlat is the longest a chip waited for rom_ok after a new address.
// chk_start reads 256 KB of the sample ROMs from SDRAM (chk_seg: 0-3 OKI1, 4-7 OKI2) through the port, between
// the caches' fetches, into chk_sum: per granule, sum = rotl(sum, 1) ^ dword 0 ^ dword 1 rotated by 16, the
// dwords little-endian (scripts/oki_sum.py computes the image's).

module gs_sound #(
	parameter [26:0] OKI1_BASE = 27'h0300000,
	parameter [26:0] OKI2_BASE = 27'h0400000
) (
	input               clk,
	input               rst,
	input               dl,               // the ROMs are being downloaded: invalidate the caches

	input       [1:0]   wr,               // one-clock strobes, chip 1 in bit 0
	input       [7:0]   din,
	output      [7:0]   dout1,
	output      [7:0]   dout2,
	input       [1:0]   bank1,
	input       [1:0]   bank2,

	// SDRAM (sdram.sv's toggle protocol): one 64-bit granule per request
	output reg  [26:1]  sd_addr,
	output reg          sd_req,
	input               sd_ack,
	input       [63:0]  sd_dout,

	input               filt_off,         // the output low-pass bypassed (OSD)
	output signed [15:0] out,

	input               dbg_clr,
	output reg  [15:0]  dbg_late1 = 16'd0,
	output reg  [15:0]  dbg_late2 = 16'd0,
	output reg  [11:0]  dbg_maxlat1 = 12'd0,
	output reg  [11:0]  dbg_maxlat2 = 12'd0,
	input               chk_start,
	input       [2:0]   chk_seg,
	output reg          chk_busy = 1'b0,
	output reg  [31:0]  chk_sum = 32'd0
);

reg  [7:0] acc = 8'd0;
reg        cen = 1'b0;
always @(posedge clk) begin
	cen <= acc >= 8'd239;
	acc <= acc >= 8'd239 ? acc - 8'd239 : acc + 8'd4;
end

wire        [17:0] rom_addr [0:1];
wire        [7:0]  rom_data [0:1];
wire               rom_ok   [0:1];
wire signed [13:0] snd      [0:1];
wire        [7:0]  dout     [0:1];
wire               br_req   [0:1];
wire               br_valid [0:1];
wire        [19:0] br_addr  [0:1];
wire        [7:0]  br_data  [0:1];
wire               g_req    [0:1];
wire        [25:0] g_addr   [0:1];
reg                g_valid  [0:1];
reg         [63:0] g_data;

genvar c;
generate for (c = 0; c < 2; c = c + 1) begin : chip
	jt6295 #(.INTERPOL(0)) u_oki (
		.rst(rst), .clk(clk), .cen(cen), .ss(1'b1),
		.wrn(~wr[c]), .din(din), .dout(dout[c]),
		.rom_addr(rom_addr[c]), .rom_data(rom_data[c]), .rom_ok(rom_ok[c]),
		.sound(snd[c]), .sample()
	);
	oki_rom_bridge u_bridge (
		.clk(clk), .reset(rst),
		.rom_addr(rom_addr[c]), .rom_data(rom_data[c]), .rom_ok(rom_ok[c]), .bank(c == 0 ? bank1 : bank2),
		.req(br_req[c]), .addr(br_addr[c]), .valid(br_valid[c]), .data(br_data[c])
	);
	sample_cache #(.ENTRIES(8)) u_cache (
		.clk(clk), .reset(rst), .inval(dl),
		.req(br_req[c]), .addr({6'd0, br_addr[c]}), .valid(br_valid[c]), .data(br_data[c]),
		.g_req(g_req[c]), .g_addr(g_addr[c]), .g_valid(g_valid[c]), .g_data(g_data)
	);
end endgenerate
assign dout1 = dout[0];
assign dout2 = dout[1];

// one granule in flight; when both caches ask, the one not served last goes first; the check's reads when neither does
reg  sd_busy, last, serve_chk = 1'b0, chk_d = 1'b0;
reg  [14:0] chk_g = 15'd0;
wire want0 = g_req[0] && !g_valid[0], want1 = g_req[1] && !g_valid[1];
wire who   = want1 && (!last || !want0);
wire [26:0] chk_base = (chk_seg[2] ? OKI2_BASE : OKI1_BASE) + {7'd0, chk_seg[1:0], 18'd0};
always @(posedge clk) begin
	g_valid[0] <= 1'b0;
	g_valid[1] <= 1'b0;
	chk_d <= chk_start;
	if (chk_start && !chk_d) begin chk_busy <= 1'b1; chk_g <= 15'd0; chk_sum <= 32'd0; end
	if (rst) begin
		sd_busy <= 1'b0;
		sd_req <= sd_ack;
		last <= 1'b1;
		serve_chk <= 1'b0;
	end else if (!sd_busy) begin
		if (want0 || want1) begin
			sd_addr <= (who ? OKI2_BASE[26:1] : OKI1_BASE[26:1]) + {1'b0, g_addr[who][25:1]};
			sd_req <= ~sd_req;
			sd_busy <= 1'b1;
			last <= who;
			serve_chk <= 1'b0;
		end else if (chk_busy) begin
			sd_addr <= chk_base[26:1] + {9'd0, chk_g, 2'd0};
			sd_req <= ~sd_req;
			sd_busy <= 1'b1;
			serve_chk <= 1'b1;
		end
	end else if (sd_req == sd_ack) begin
		sd_busy <= 1'b0;
		if (serve_chk) begin
			chk_sum <= {chk_sum[30:0], chk_sum[31]} ^ sd_dout[31:0] ^ {sd_dout[47:32], sd_dout[63:48]};
			chk_g <= chk_g + 15'd1;
			if (&chk_g) chk_busy <= 1'b0;
		end else begin
			g_data <= sd_dout;
			g_valid[last] <= 1'b1;
		end
	end
end

// the late ADPCM bytes and the longest wait for rom_ok
wire t_sr4, t_sr32;
jt6295_timing u_tm (
	.clk(clk), .cen(cen), .ss(1'b1),
	.cen_sr(), .cen_sr4(t_sr4), .cen_sr4b(), .cen_sr32(t_sr32), .cen_48k()
);
reg  [7:0]  t_st;
always @(posedge clk) begin
	if (t_sr4) t_st <= 8'h80;
	else if (t_sr32) t_st <= {t_st[6:0], t_st[7]};
end
wire        t_take = t_st == 8'h02 && (t_sr4 || t_sr32);
reg  [17:0] lat_a1 = 18'd0, lat_a2 = 18'd0;
reg  [11:0] lat_n1 = 12'd0, lat_n2 = 12'd0;
always @(posedge clk) begin
	lat_a1 <= rom_addr[0];
	lat_a2 <= rom_addr[1];
	lat_n1 <= rom_addr[0] != lat_a1 ? 12'd0 : (!rom_ok[0] && lat_n1 != 12'hfff) ? lat_n1 + 12'd1 : lat_n1;
	lat_n2 <= rom_addr[1] != lat_a2 ? 12'd0 : (!rom_ok[1] && lat_n2 != 12'hfff) ? lat_n2 + 12'd1 : lat_n2;
	if (lat_n1 > dbg_maxlat1) dbg_maxlat1 <= lat_n1;
	if (lat_n2 > dbg_maxlat2) dbg_maxlat2 <= lat_n2;
	if (t_take && !rom_ok[0] && dbg_late1 != 16'hffff) dbg_late1 <= dbg_late1 + 16'd1;
	if (t_take && !rom_ok[1] && dbg_late2 != 16'hffff) dbg_late2 <= dbg_late2 + 16'd1;
	if (dbg_clr) begin dbg_late1 <= 16'd0; dbg_late2 <= 16'd0; dbg_maxlat1 <= 12'd0; dbg_maxlat2 <= 12'd0; end
end

wire signed [18:0] mix = {{1{snd[0][13]}}, snd[0], 4'd0} + {{1{snd[1][13]}}, snd[1], 4'd0};
wire signed [15:0] mixc = (mix > 19'sd32767) ? 16'sd32767 : (mix < -19'sd32768) ? -16'sd32768 : mix[15:0];

// The output low-pass, modelled bit for bit by scripts/snd_filter.py: a 4th-order Butterworth at 3.5 kHz, two
// biquads in direct form I on a sample every 1266 clocks (47,986 Hz), one multiply-add a clock through the ten
// products. The chips hold each sample for 132 us; unfiltered, the steps put images above the 3.79 kHz Nyquist
// that MAME's resampler removes (sim/sys_tb +wav: 0.17% of the energy at 3.8-8 kHz, MAME's 0.02%).
localparam integer FB = 4, SW = 22;                  // fraction bits in the sections' samples, their width
reg  signed [24:0]   f_c;
reg  signed [SW-1:0] f_op, f_v;
reg  signed [SW-1:0] f_x1 [0:1], f_x2 [0:1], f_y1 [0:1], f_y2 [0:1];
reg  signed [49:0]   f_acc;
reg         [10:0]   f_div = 11'd0;
reg         [3:0]    f_k = 4'd15;                    // 0-4 section 0's products, 5 its result, 6-11 section 1's; 15 idle
reg  signed [15:0]   f_out = 16'sd0;
wire                 f_sec = f_k >= 4'd6;
wire        [3:0]    f_t = f_sec ? f_k - 4'd6 : f_k;
wire signed [27:0]   f_q = f_acc >>> 22;
wire signed [SW-1:0] f_y = f_q > 28'sd2097151 ? 22'sd2097151 : f_q < -28'sd2097152 ? -22'sd2097152 : f_q[SW-1:0];
wire signed [17:0]   f_o = f_y >>> FB;
always @* begin
	case (f_k)
		4'd0:  f_c = 25'sd153613;   4'd1: f_c = 25'sd307225;   4'd2:  f_c = 25'sd153613;
		4'd3:  f_c = 25'sd5340263;  4'd4: f_c = -25'sd1760410;                                  // -a1, -a2
		4'd6:  f_c = 25'sd185067;   4'd7: f_c = 25'sd370134;   4'd8:  f_c = 25'sd185067;
		4'd9:  f_c = 25'sd6433755; 4'd10: f_c = -25'sd2979719;
		default: f_c = 25'sd0;
	endcase
	case (f_t)
		4'd0: f_op = f_v;
		4'd1: f_op = f_x1[f_sec];
		4'd2: f_op = f_x2[f_sec];
		4'd3: f_op = f_y1[f_sec];
		default: f_op = f_y2[f_sec];
	endcase
end
always @(posedge clk) begin
	f_div <= f_div == 11'd1265 ? 11'd0 : f_div + 11'd1;
	if (rst) begin
		f_k <= 4'd15;
		f_x1[0] <= 0; f_x2[0] <= 0; f_y1[0] <= 0; f_y2[0] <= 0;
		f_x1[1] <= 0; f_x2[1] <= 0; f_y1[1] <= 0; f_y2[1] <= 0;
		f_out <= 16'sd0;
	end else if (f_div == 11'd0) begin
		f_k <= 4'd0;
		f_v <= {{2{mixc[15]}}, mixc, 4'd0};
		f_acc <= 50'sd0;
	end else if (f_k != 4'd15) begin
		if (f_t == 4'd5) begin
			f_x2[f_sec] <= f_x1[f_sec]; f_x1[f_sec] <= f_v;
			f_y2[f_sec] <= f_y1[f_sec]; f_y1[f_sec] <= f_y;
			f_v <= f_y;
			f_acc <= 50'sd0;
			if (f_sec) f_out <= f_o > 18'sd32767 ? 16'sd32767 : f_o < -18'sd32768 ? -16'sd32768 : f_o[15:0];
			f_k <= f_sec ? 4'd15 : f_k + 4'd1;
		end else begin
			f_acc <= f_acc + f_c * f_op;
			f_k <= f_k + 4'd1;
		end
	end
end
assign out = filt_off ? mixc : f_out;

endmodule
