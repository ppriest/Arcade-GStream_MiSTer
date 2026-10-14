// SPDX-License-Identifier: GPL-3.0-or-later
// System bench top: the main board (gs_main), the video (gs_video), the sound (gs_sound), the real SDRAM
// controller and a command-decoding chip model, with the clock enables GStream.sv makes. main.cpp loads the
// download image's SDRAM part into the chip model's array, the backup RAM's default through nv_load_*, the
// empty-tile table through et_*, answers the video's DDR3 reads from the image, and drives the inputs.

module tb_sys (
	input             clk,
	input             prst,
	input             rst,
	input             x2,
	input             pause,
	input      [15:0] in0,
	input      [15:0] in1,

	input             et_we,
	input      [12:0] et_addr,
	input      [7:0]  et_data,
	output            gfx_rd,
	output     [27:3] gfx_addr,
	output     [7:0]  gfx_burst,
	input             gfx_busy,
	input             gfx_dv,
	input      [63:0] gfx_dout,

	input             nv_blank,
	input             nv_load,
	input             nv_load_we,
	input      [12:0] nv_load_addr,
	input      [7:0]  nv_load_data,

	output            ce_pix,
	output     [7:0]  vid_r,
	output     [7:0]  vid_g,
	output     [7:0]  vid_b,
	output            hblank,
	output            vblank,
	output            vblank_irq,

	output            retire,
	output     [31:0] retire_pc,
	output     [31:0] st_imiss,
	output     [31:0] st_dmiss,
	output     [15:0] vid_overrun,
	output     [11:0] vid_maxbusy,
	output signed [15:0] snd,
	output        [15:0] oki_late1,
	output        [15:0] oki_late2,
	output        [11:0] oki_maxlat1,
	output        [11:0] oki_maxlat2
);

// clk_sys 60.75 MHz: the CPU's 64 MHz timer is a tick every clock and a second in 13 of 243
reg [7:0] tk = 8'd0;
reg       tick2 = 1'b0;
always @(posedge clk) begin
	tick2 <= tk >= 8'd230;
	tk <= tk >= 8'd230 ? tk - 8'd230 : tk + 8'd13;
end

wire [26:1] m2_addr;
wire        m2_wrl, m2_wrh, m2_dbl, m2_req, m2_ack;
wire [15:0] m2_din;
wire [47:0] m2_dinx;
wire  [5:0] m2_wrx;
wire [63:0] m2_dout, m2_doutb;
wire [26:1] s1_addr;
wire        s1_req, s1_ack;
wire [63:0] s1_dout;

wire        spr_we, pal_we;
wire [3:0]  spr_be, pal_be;
wire [11:0] spr_addr;
wire [12:0] pal_addr;
wire [31:0] spr_wd, pal_wd, spr_rd, pal_rd;
wire [1:0]  oki_wr, oki_bank1, oki_bank2;
wire [7:0]  oki_wd, oki_dout1, oki_dout2;
wire [15:0] scrollx0, scrolly0, scrollx1, scrolly1, scrollx2, scrolly2;

gs_main u_main (
	.clk(clk), .prst(prst), .rst(rst), .x2(x2), .pause(pause), .cpu_tick(1'b1), .cpu_tick2(tick2),
	.vblank_irq(vblank_irq), .in0(in0), .in1(in1),
	.x_p1(8'hff), .x_p2(8'hff), .x_sys(8'hff), .x_dsw(8'hff), .x_in4(7'h7f),
	.spr_we(spr_we), .spr_be(spr_be), .spr_addr(spr_addr), .spr_wd(spr_wd), .spr_rd(spr_rd),
	.pal_we(pal_we), .pal_be(pal_be), .pal_addr(pal_addr), .pal_wd(pal_wd), .pal_rd(pal_rd),
	.scrollx0(scrollx0), .scrolly0(scrolly0), .scrollx1(scrollx1), .scrolly1(scrolly1),
	.scrollx2(scrollx2), .scrolly2(scrolly2),
	.oki_wr(oki_wr), .oki_wd(oki_wd), .oki_dout1(oki_dout1), .oki_dout2(oki_dout2),
	.oki_bank1(oki_bank1), .oki_bank2(oki_bank2),
	.nv_blank(nv_blank), .nv_load(nv_load), .nv_load_we(nv_load_we), .nv_load_addr(nv_load_addr),
	.nv_load_data(nv_load_data), .nv_rd_addr(13'd0), .nv_rd_data(), .nv_written(),
	.dl_req(1'b0), .dl_addr(27'd0), .dl_data(16'd0), .dl_we16(1'b0), .dl_g(1'b0), .dl_gdata(64'd0), .dl_busy(),
	.mem_addr(m2_addr), .mem_wrl(m2_wrl), .mem_wrh(m2_wrh), .mem_din(m2_din), .mem_dinx(m2_dinx),
	.mem_wrx(m2_wrx), .mem_dbl(m2_dbl), .mem_req(m2_req), .mem_ack(m2_ack),
	.mem_dout(m2_dout), .mem_doutb(m2_doutb),
	.retire(retire), .retire_pc(retire_pc), .retire_npc(), .retire_sr(),
	.st_imiss(st_imiss), .st_dmiss(st_dmiss), .dbg_rf_we(), .dbg_rf_wa(), .dbg_rf_wd(),
	.trace_start(24'hffffff), .trace_idx(12'd0), .trace_valid(), .trace_rec(), .trace_q(), .trace_count()
);

gs_video u_video (
	.clk(clk), .rst(rst),
	.spr_we(spr_we), .spr_be(spr_be), .spr_addr(spr_addr), .spr_wd(spr_wd), .spr_rd(spr_rd),
	.pal_we(pal_we), .pal_be(pal_be), .pal_addr(pal_addr), .pal_wd(pal_wd), .pal_rd(pal_rd),
	.scrollx0(scrollx0), .scrolly0(scrolly0), .scrollx1(scrollx1), .scrolly1(scrolly1),
	.scrollx2(scrollx2), .scrolly2(scrolly2), .flip(1'b0),
	.et_we(et_we), .et_addr(et_addr), .et_data(et_data),
	.gfx_rd(gfx_rd), .gfx_addr(gfx_addr), .gfx_burst(gfx_burst), .gfx_busy(gfx_busy), .gfx_dv(gfx_dv), .gfx_dout(gfx_dout),
	.ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(), .vsync(), .vblank_irq(vblank_irq),
	.r(vid_r), .g(vid_g), .b(vid_b), .dbg_overrun(vid_overrun), .dbg_maxbusy(vid_maxbusy)
);

gs_sound u_snd (
	.clk(clk), .rst(rst), .dl(1'b0),
	.wr(oki_wr), .din(oki_wd), .dout1(oki_dout1), .dout2(oki_dout2), .bank1(oki_bank1), .bank2(oki_bank2),
	.sd_addr(s1_addr), .sd_req(s1_req), .sd_ack(s1_ack), .sd_dout(s1_dout),
	.filt_off(1'b0), .out(snd),
	.dbg_clr(1'b0), .dbg_late1(oki_late1), .dbg_late2(oki_late2), .dbg_maxlat1(oki_maxlat1), .dbg_maxlat2(oki_maxlat2),
	.chk_start(1'b0), .chk_seg(3'd0), .chk_busy(), .chk_sum()
);

wire [15:0] SDRAM_DQ;
wire [12:0] SDRAM_A;
wire  [1:0] SDRAM_BA;
wire        SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CLK, SDRAM_CKE;

// a chip needs a refresh every 7.8125 us, 474 clocks at 60.75 MHz; the two chips alternate
sdram #(.RFS_INTERVAL(10'd237)) u_sdram (
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE),
	.init(1'b0), .clk(clk), .rd_adj(2'd0),
	.addr0(26'd0), .wrl0(1'b0), .wrh0(1'b0), .din0(16'd0), .dout0(), .req0(1'b0), .ack0(), .dbl0(1'b0), .dout0b(),
	.addr1(s1_addr), .wrl1(1'b0), .wrh1(1'b0), .din1(16'd0), .dout1(s1_dout), .req1(s1_req), .ack1(s1_ack), .dbl1(1'b0), .dout1b(),
	.addr2(m2_addr), .wrl2(m2_wrl), .wrh2(m2_wrh), .din2(m2_din), .din2x(m2_dinx), .wrx2(m2_wrx),
	.dout2(m2_dout), .req2(m2_req), .ack2(m2_ack), .dbl2(m2_dbl), .dout2b(m2_doutb)
);

sdram_chip_model_wide u_chip (
	.clk(clk), .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS)
);

endmodule
