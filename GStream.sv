// SPDX-License-Identifier: GPL-3.0-or-later
// GStream: MiSTer top level for MAME's promat/gstream.cpp (G-Stream G2020 and X2222).
//
// Framework glue only: hps_io, PLL and resets, ROM load through DDR3, inputs, backup RAM and video output.
// The board is rtl/gs_main.sv, rtl/video/gs_video.sv and rtl/sound/gs_sound.sv.
// clk_sys is 60.75 MHz for the whole design. The image is loaded at DDR3 0x30000000; its first 5 MB
// (CPU ROMs and samples) are copied to SDRAM, the graphics stay in DDR3 (docs/ROADMAP.md).

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign FB_FORCE_BLANK = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS   = 0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = 2'd0;

//////////////////////////////////////////////////////////////////

`include "rtl/gs_sdram_map.svh"
`include "build_id.v"

wire [1:0] ar = status[122:121];

// All sets are ROT270 (gstream.cpp 1134): Auto rotates counter-clockwise.
wire [1:0] rot_sel    = status[64:63];
wire       rotate_en  = rot_sel != 2'd1;
wire       rotate_ccw = rot_sel == 2'd0 || rot_sel == 2'd3;

wire [11:0] base_arx = rotate_en ? 12'd3 : 12'd4;
wire [11:0] base_ary = rotate_en ? 12'd4 : 12'd3;

`ifdef DEBUG_ISSP
localparam DEBUG_MENU_HIDE = 1'b0;
`else
localparam DEBUG_MENU_HIDE = 1'b1;
`endif

localparam CONF_STR = {
	"GStream;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[64:63],Rotation,Auto,Off,CW,CCW;",
	"O[65],Flip Screen,Off,On;",
	"DIP;",
	"O[68:66],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"O[46:44],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O[69],Audio Filter,On,Off;",
	"-;",
	"O[94],CRT adjust,Off,On;",
	"H3O[99:95],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H3O[106:100],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H3O[112:107],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"H1P1,Debug;",
	"H1P1-;",
	"H1P1O[82],Pause CPU,Off,On;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	// entry i is joystick bit 4 + i, matching the .mra <buttons>
	"J1,Button 1,Button 2,Button 3,Button 4,Start,Coin,Pause,Service Coin,Service Mode;",
	"jn,A,B,X,Y,Start,Select,L,R;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire  [21:0] gamma_bus;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire [31:0] joystick_0, joystick_1;

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_wait;
wire  [7:0] ioctl_din;
wire        ioctl_upload;
reg         nvram_save = 1'b0;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({12'd0, ~status[94], 1'b0, DEBUG_MENU_HIDE, 1'b0}),   // H1 Debug, H3 CRT adjust

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	// the .mra's <nvram index="4" size="8192"/>: the backup RAM
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(nvram_save),
	.ioctl_upload_index(8'd4),
	.ioctl_din(ioctl_din),
	.ioctl_rd(),

	.ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys, clk_sdram_shifted, pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram_shifted),
	.locked(pll_locked)
);

assign SDRAM_CLK = clk_sdram_shifted;

///////////////////////   RESET, ROM LOAD   //////////////////////

wire reset = RESET | status[0] | buttons[1] | ~pll_locked;

// Hold the game, not the memory path, until the ROM copy and empty-tile scan finish
// (Arcade-Vamphalf_MiSTer's Limenko.sv).
wire ldr_active, et_busy;
reg  rom_loaded = 1'b0, et_start = 1'b0, ldr_active_d = 1'b0;
always @(posedge clk_sys) begin
	ldr_active_d <= ldr_active;
	et_start <= ldr_active_d && !ldr_active;          // the copy finished: scan the sprites
	if (et_start) rom_loaded <= 1'b0;
	else if (!et_busy && !et_start && ldr_done && !ldr_active) rom_loaded <= 1'b1;
end
wire dbg_hold;
wire load_busy  = ldr_active | et_busy | et_start;
wire core_reset = reset | ioctl_download | ~rom_loaded | load_busy | dbg_hold;

// Fast ROM load: the HPS writes index 0 to DDR3 when the .mra sets address="0x30000000" (no ioctl_wr).
// On the next reset release, copy the SDRAM part once. Video DDR3 reads are held until the copy starts,
// because ddram_phy would take their data (Limenko.sv); the hold is 256 clocks.
reg  dl0_d = 1'b0, dl0_seen = 1'b0, dl_seen_wr = 1'b0, ldr_pending = 1'b0, ldr_start = 1'b0, ldr_done = 1'b0;
wire dl0 = ioctl_download && ioctl_index == 16'd0;
wire vid_rst = ~pll_locked | core_reset | ldr_pending | ldr_start;
reg  [8:0] vid_quiet = 9'd0;
always @(posedge clk_sys) vid_quiet <= !vid_rst ? 9'd0 : vid_quiet[8] ? vid_quiet : vid_quiet + 9'd1;

always @(posedge clk_sys) begin
	ldr_start <= 1'b0;
	dl0_d <= dl0;
	if (dl0 && !dl0_d) begin
		dl0_seen   <= 1'b1;
		dl_seen_wr <= 1'b0;
		ldr_done   <= 1'b0;
	end else if (dl0 && ioctl_wr) dl_seen_wr <= 1'b1;
	if (reset) ldr_pending <= 1'b1;
	else if (ldr_pending && !ioctl_download && !load_busy && vid_quiet[8]) begin
		ldr_pending <= 1'b0;
		if (dl0_seen && !dl_seen_wr && !ldr_done) begin
			ldr_start <= 1'b1;
			ldr_done  <= 1'b1;
		end
	end
end

///////////////////   .mra: mod byte, switches   ////////////////

// <rom index="1"> (scripts/build_mra.py): [0] X2222's map
reg [7:0] mod_byte = 8'd0;
always @(posedge clk_sys) if (ioctl_wr && ioctl_index == 16'd1 && ioctl_addr == 27'd0) mod_byte <= ioctl_dout;
wire x2 = mod_byte[0];

// <switches> (ioctl index 254): X2222's DSW, SYS bits 7:4 and 1, IN4 bits 6:0, as the CPU reads them.
// gstream has no DIP in MAME. Defaults are MAME's until a .mra sends switches.
reg [7:0] sw0 = 8'h0d, sw1 = 8'hff, sw2 = 8'hff;
always @(posedge clk_sys)
	if (ioctl_wr && ioctl_index == 16'd254) case (ioctl_addr[1:0])
		2'd0: sw0 <= ioctl_dout;
		2'd1: sw1 <= ioctl_dout;
		2'd2: sw2 <= ioctl_dout;
		default: ;
	endcase

///////////////////////   INPUTS   ///////////////////////////////

// MiSTer joystick: 0 R, 1 L, 2 D, 3 U, buttons 1-4 at 4-7, Start 8, Coin 9, Pause 10, Service Coin 11,
// Service Mode 12. MAME's default keys (rtl/mame_keys.sv) ORed into the pads.
wire [31:0] key0, key1;
wire  [1:0] svc_coin;
mame_keys #(.BUTTONS(4), .START(8), .COIN(9), .PAUSE(10), .SERVICE(12)) u_keys (
	.clk(clk_sys), .ps2_key(ps2_key), .key0(key0), .key1(key1), .svc_coin(svc_coin)
);
wire [31:0] joy0 = joystick_0 | key0;
wire [31:0] joy1 = joystick_1 | key1;
wire        svc_mode = joy0[12] | joy1[12];

// gstream IN0 / IN1 (gstream.cpp 402-438), active high here: 0 U, 1 D, 2 L, 3 R, 4-7 buttons 1-4, 9 coin, 10 start,
// 11 service, 15 the test switch (IN0's; gs_main mirrors it into IN1 and IN2)
function automatic [15:0] gs_pl(input [31:0] j, input svc, input test);
	gs_pl = {test, 3'b000, svc, j[8], j[9], 1'b0, j[7], j[6], j[5], j[4], j[0], j[1], j[2], j[3]};
endfunction
wire [15:0] in0 = ~gs_pl(joy0, joy0[11] | svc_coin[0], svc_mode);
wire [15:0] in1 = ~gs_pl(joy1, joy1[11] | svc_coin[1], 1'b0);
// X2222 P1 / P2 (441-460): 0 U, 1 D, 2 L, 3 R, 4-5 buttons 1-2; SYS: 0 coin 1, 2 start 1, 3 start 2, the rest DIPs
wire [7:0]  x_p1  = ~{2'b00, joy0[5], joy0[4], joy0[0], joy0[1], joy0[2], joy0[3]};
wire [7:0]  x_p2  = ~{2'b00, joy1[5], joy1[4], joy1[0], joy1[1], joy1[2], joy1[3]};
wire [7:0]  x_sys = {sw1[7:4], ~joy1[8], ~joy0[8], sw1[1], ~(joy0[9] | joy1[9])};

// Pause: joystick bit 10 (or P) toggles; the Debug page's Pause CPU is ORed in
wire pause_btn = joy0[10] | joy1[10];
reg  pause_btn_d = 1'b0, pause_toggle = 1'b0;
always @(posedge clk_sys) begin
	pause_btn_d <= pause_btn;
	if (reset)                         pause_toggle <= 1'b0;
	else if (pause_btn & ~pause_btn_d) pause_toggle <= ~pause_toggle;
end
wire pause_cpu = pause_toggle | status[82];

///////////////////////   BACKUP RAM   ///////////////////////////

// gstream's backup RAM: zeroed at the start of each index-0 download (X2222's plain RAM is kept), then
// MAME's default image (<rom index="2">) and a saved .nvm (<nvram index="4">) load it. A save is requested
// one second after the game's last write.
reg [11:0] nv_blank_n = 12'd0;
always @(posedge clk_sys)
	if (dl0 && !dl0_d) nv_blank_n <= 12'd2100;
	else if (nv_blank_n != 12'd0) nv_blank_n <= nv_blank_n - 12'd1;
wire        nv_blank = nv_blank_n != 12'd0;
wire        nv_load  = ioctl_download && (ioctl_index == 16'd2 || ioctl_index == 16'd4);
wire        nv_ld_we = ioctl_wr && nv_load && ioctl_addr[26:13] == 14'd0;
wire  [7:0] nv_rd_data;
wire        nv_written;
assign ioctl_din = nv_rd_data;
reg  [25:0] nv_quiet = 26'd0;
reg         nv_dirty = 1'b0;
always @(posedge clk_sys) begin
	nvram_save <= 1'b0;
	if (nv_written && !x2) begin
		nv_dirty <= 1'b1;
		nv_quiet <= 26'd0;
	end else if (nv_dirty) begin
		nv_quiet <= nv_quiet + 26'd1;
		if (nv_quiet == 26'd60_750_000) begin
			nv_dirty   <= 1'b0;
			nvram_save <= 1'b1;
		end
	end
end

///////////////////////   THE BOARD   ////////////////////////////

// the E1's 64 MHz (16 MHz x 4) as timer ticks: one every clock, a second in 13 of every 243
reg [7:0] tk = 8'd0;
reg       cpu_tick2 = 1'b0;
always @(posedge clk_sys) begin
	cpu_tick2 <= tk >= 8'd230;
	tk <= tk >= 8'd230 ? tk - 8'd230 : tk + 8'd13;
end

wire        spr_we, pal_we;
wire [3:0]  spr_be, pal_be;
wire [11:0] spr_addr;
wire [12:0] pal_addr;
wire [31:0] spr_wd, pal_wd, spr_rd, pal_rd;
wire [15:0] scrollx0, scrolly0, scrollx1, scrolly1, scrollx2, scrolly2;
wire [1:0]  oki_wr, oki_bank1, oki_bank2;
wire [7:0]  oki_wd, oki_dout1, oki_dout2;
wire        vblank_irq;

wire        dl_req, dl_we16, dl_busy;
wire [26:0] dl_addr;
wire [15:0] dl_data;
wire        bdl_req;
wire [26:0] bdl_addr;
wire        ldl_req;
wire [26:0] ldl_addr;
wire [63:0] ldl_gdata;

// the byte path (a .mra without address="0x30000000"); the fast load's copy otherwise
sdram_download u_dl (
	.clk(clk_sys), .reset(~pll_locked),
	.ioctl_download(ioctl_download && ioctl_index == 16'd0), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr && ioctl_index == 16'd0),
	.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_wait(ioctl_wait),
	.dl_req(bdl_req), .dl_addr(bdl_addr), .dl_data(dl_data), .dl_we16(dl_we16), .dl_busy(ldr_active ? 1'b0 : dl_busy)
);

wire        ldr_ddr_req, ldr_ddr_busy, ldr_ddr_valid;
wire [27:0] ldr_ddr_addr;
wire [63:0] ldr_ddr_rdata;
wire [7:0]  ldr_DDRAM_BURSTCNT, ldr_DDRAM_BE;
wire [28:0] ldr_DDRAM_ADDR;
wire [63:0] ldr_DDRAM_DIN;
wire        ldr_DDRAM_RD, ldr_DDRAM_WE;
wire        ld_busy, ld_dv;
ddram_phy u_ldr_ddram (
	.clk(clk_sys), .reset(~pll_locked),
	.DDRAM_BUSY(ld_busy), .DDRAM_BURSTCNT(ldr_DDRAM_BURSTCNT),
	.DDRAM_ADDR(ldr_DDRAM_ADDR), .DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(ld_dv), .DDRAM_RD(ldr_DDRAM_RD),
	.DDRAM_DIN(ldr_DDRAM_DIN), .DDRAM_BE(ldr_DDRAM_BE), .DDRAM_WE(ldr_DDRAM_WE),
	.req(ldr_ddr_req), .we(1'b0), .addr(ldr_ddr_addr), .wdata(8'd0),
	.busy(ldr_ddr_busy), .valid(ldr_ddr_valid), .rdata(ldr_ddr_rdata)
);

vh_rom_loader u_ldr (
	.clk(clk_sys), .reset(~pll_locked),
	.length({1'b0, SD_SDRAM_END}),
	.start(ldr_start), .busy(ldr_active),
	.ddr_req(ldr_ddr_req), .ddr_addr(ldr_ddr_addr), .ddr_busy(ldr_ddr_busy),
	.ddr_valid(ldr_ddr_valid), .ddr_rdata(ldr_ddr_rdata),
	.dl_req(ldl_req), .dl_addr(ldl_addr), .dl_gdata(ldl_gdata), .dl_busy(ldr_active ? dl_busy : 1'b0),
	.tap_addr(), .tap_want(1'b0),
	.tb_wr(), .tb_addr(), .tb_dout()
);

assign dl_req  = ldr_active ? ldl_req  : bdl_req;
assign dl_addr = ldr_active ? ldl_addr : bdl_addr;

wire        et_rd, et_we;
wire [28:0] et_ddr_addr;
wire [7:0]  et_burst, et_data;
wire [12:0] et_addr;
gs_et_scan #(.BASE({1'b0, SD_SPR})) u_et (
	.clk(clk_sys), .start(et_start), .busy(et_busy),
	.rd(et_rd), .addr(et_ddr_addr), .burst(et_burst), .ddr_busy(ld_busy), .dv(ld_dv), .dout(DDRAM_DOUT),
	.et_we(et_we), .et_addr(et_addr), .et_data(et_data)
);

wire [26:1] m2_addr;
wire        m2_wrl, m2_wrh, m2_dbl, m2_req, m2_ack;
wire [15:0] m2_din;
wire [47:0] m2_dinx;
wire  [5:0] m2_wrx;
wire [63:0] m_dout, m_doutb;

wire        dbg_retire;
wire [31:0] dbg_pc, dbg_imiss, dbg_dmiss;

gs_main u_main (
	.clk(clk_sys), .prst(~pll_locked), .rst(core_reset), .x2(x2), .pause(pause_cpu),
	.cpu_tick(1'b1), .cpu_tick2(cpu_tick2),
	.vblank_irq(vblank_irq), .in0(in0), .in1(in1),
	.x_p1(x_p1), .x_p2(x_p2), .x_sys(x_sys), .x_dsw(sw0), .x_in4(sw2[6:0]),
	.spr_we(spr_we), .spr_be(spr_be), .spr_addr(spr_addr), .spr_wd(spr_wd), .spr_rd(spr_rd),
	.pal_we(pal_we), .pal_be(pal_be), .pal_addr(pal_addr), .pal_wd(pal_wd), .pal_rd(pal_rd),
	.scrollx0(scrollx0), .scrolly0(scrolly0), .scrollx1(scrollx1), .scrolly1(scrolly1),
	.scrollx2(scrollx2), .scrolly2(scrolly2),
	.oki_wr(oki_wr), .oki_wd(oki_wd), .oki_dout1(oki_dout1), .oki_dout2(oki_dout2),
	.oki_bank1(oki_bank1), .oki_bank2(oki_bank2),
	.nv_blank(nv_blank), .nv_load(nv_load), .nv_load_we(nv_ld_we), .nv_load_addr(ioctl_addr[12:0]),
	.nv_load_data(ioctl_dout), .nv_rd_addr(ioctl_addr[12:0]), .nv_rd_data(nv_rd_data), .nv_written(nv_written),
	.dl_req(dl_req), .dl_addr(dl_addr), .dl_data(dl_data), .dl_we16(dl_we16), .dl_g(ldr_active), .dl_gdata(ldl_gdata),
	.dl_busy(dl_busy),
	.mem_addr(m2_addr), .mem_wrl(m2_wrl), .mem_wrh(m2_wrh), .mem_din(m2_din), .mem_dinx(m2_dinx), .mem_wrx(m2_wrx),
	.mem_dbl(m2_dbl), .mem_req(m2_req), .mem_ack(m2_ack), .mem_dout(m_dout), .mem_doutb(m_doutb),
	.retire(dbg_retire), .retire_pc(dbg_pc), .retire_npc(), .retire_sr(), .st_imiss(dbg_imiss), .st_dmiss(dbg_dmiss),
	.dbg_rf_we(), .dbg_rf_wa(), .dbg_rf_wd(),
	.trace_start(24'hffffff), .trace_idx(12'd0), .trace_valid(), .trace_rec(), .trace_q(), .trace_count()
);

wire [7:0]  core_r, core_g, core_b;
wire        core_hs, core_vs, core_hb, core_vb, core_ce;
wire        v_rd, v_busy, v_dv;
wire [27:3] v_addr;
wire [7:0]  v_burst;
wire [15:0] dbg_overrun;

gs_video #(.SPR_BASE({1'b0, SD_SPR}), .TILE_BASE({1'b0, SD_TILE0})) u_video (
	.clk(clk_sys), .rst(vid_rst),
	.spr_we(spr_we), .spr_be(spr_be), .spr_addr(spr_addr), .spr_wd(spr_wd), .spr_rd(spr_rd),
	.pal_we(pal_we), .pal_be(pal_be), .pal_addr(pal_addr), .pal_wd(pal_wd), .pal_rd(pal_rd),
	.scrollx0(scrollx0), .scrolly0(scrolly0), .scrollx1(scrollx1), .scrolly1(scrolly1),
	.scrollx2(scrollx2), .scrolly2(scrolly2), .flip(status[65]),
	.et_we(et_we), .et_addr(et_addr), .et_data(et_data),
	.gfx_rd(v_rd), .gfx_addr(v_addr), .gfx_burst(v_burst), .gfx_busy(v_busy), .gfx_dv(v_dv), .gfx_dout(DDRAM_DOUT),
	.ce_pix(core_ce), .hblank(core_hb), .vblank(core_vb), .hsync(core_hs), .vsync(core_vs), .vblank_irq(vblank_irq),
	.r(core_r), .g(core_g), .b(core_b), .dbg_overrun(dbg_overrun), .dbg_maxbusy()
);

wire [26:1] m1_addr;
wire        m1_req, m1_ack;
wire [63:0] m1_dout;
wire signed [15:0] snd;
wire        dbg_snd_clr, dbg_chk_start, dbg_chk_busy;
wire [2:0]  dbg_chk_seg;
wire [15:0] dbg_late1, dbg_late2;
wire [11:0] dbg_maxlat1, dbg_maxlat2;
wire [31:0] dbg_chk_sum;
gs_sound #(.OKI1_BASE(SD_OKI1), .OKI2_BASE(SD_OKI2)) u_snd (
	.clk(clk_sys), .rst(core_reset), .dl(ioctl_download | ldr_active),
	.wr(oki_wr), .din(oki_wd), .dout1(oki_dout1), .dout2(oki_dout2), .bank1(oki_bank1), .bank2(oki_bank2),
	.sd_addr(m1_addr), .sd_req(m1_req), .sd_ack(m1_ack), .sd_dout(m1_dout),
	.filt_off(status[69]), .out(snd),
	.dbg_clr(dbg_snd_clr), .dbg_late1(dbg_late1), .dbg_late2(dbg_late2), .dbg_maxlat1(dbg_maxlat1), .dbg_maxlat2(dbg_maxlat2),
	.chk_start(dbg_chk_start), .chk_seg(dbg_chk_seg), .chk_busy(dbg_chk_busy), .chk_sum(dbg_chk_sum)
);
assign AUDIO_L = snd;
assign AUDIO_R = snd;

// a chip needs a refresh every 7.8125 us, 474 clocks at 60.75 MHz; the 128 MB module's two chips alternate
sdram #(.RFS_INTERVAL(10'd237)) u_sdram (
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(), .SDRAM_CKE(SDRAM_CKE),
	.init(~pll_locked), .clk(clk_sys), .rd_adj(2'd0),
	.addr0(26'd0), .wrl0(1'b0), .wrh0(1'b0), .din0(16'd0), .dout0(), .req0(1'b0), .ack0(), .dbl0(1'b0), .dout0b(),
	.addr1(m1_addr), .wrl1(1'b0), .wrh1(1'b0), .din1(16'd0), .dout1(m1_dout), .req1(m1_req), .ack1(m1_ack),
	.dbl1(1'b0), .dout1b(),
	.addr2(m2_addr), .wrl2(m2_wrl), .wrh2(m2_wrh), .din2(m2_din), .din2x(m2_dinx), .wrx2(m2_wrx), .dout2(m_dout),
	.req2(m2_req), .ack2(m2_ack), .dbl2(m2_dbl), .dout2b(m_doutb)
);

// Probes: GStream_stp revision only (DEBUG_ISSP); scripts/read_issp.tcl decodes them.
`ifdef DEBUG_ISSP
reg  [31:0] dbg_ninstr = 0;
reg  [7:0]  dbg_frames = 0;
always @(posedge clk_sys) begin
	if (dbg_retire) dbg_ninstr <= dbg_ninstr + 1'd1;
	if (vblank_irq) dbg_frames <= dbg_frames + 1'd1;
end
wire [7:0] dbg_src_f;
// Instance F: [31:0] instructions retired, [63:32] last retired PC, [79:64] D-misses, [95:80] I-misses, [111:96] video
// line overruns, [119:112] frames, [120] rom_loaded, [121] core_reset, [122] et_busy, [123] ioctl_download,
// [124] ldr_done, [125] ldr_active, [126] x2, [127] pll_locked
issp_probe #(.INSTANCE_ID("F"), .PROBE_W(128), .SOURCE_W(8)) u_issp_f (
	.clk(clk_sys),
	.probe({pll_locked, x2, ldr_active, ldr_done, ioctl_download, et_busy, core_reset, rom_loaded, dbg_frames, dbg_overrun,
	        dbg_imiss[15:0], dbg_dmiss[15:0], dbg_pc, dbg_ninstr}),
	.source(dbg_src_f)
);
reg  [7:0] dbg_src_f1, dbg_src_f2;
always @(posedge clk_sys) begin dbg_src_f1 <= dbg_src_f; dbg_src_f2 <= dbg_src_f1; end
assign dbg_hold = dbg_src_f2[2];

// Instance P: CPU headroom per frame, as sim/sys_tb +idle counts it. Busy clocks run from the vblank
// interrupt to the CPU's last entry into its idle loop (0xc000158c-0xc0001594); a frame that ends
// outside the loop is lost, and the game then skips its VRAM copy. Source bit 0 pulsed clears.
// [15:0] frames, [31:16] lost, [47:32] frames without a VRAM write, [63:48] frames over 0.9,
// [83:64] busiest kept frame's clocks, [103:84] last frame's (of 1,018,656 a frame)
wire [7:0] dbg_src_p;
reg  [2:0] p_clr_s = 3'd0;
always @(posedge clk_sys) p_clr_s <= {p_clr_s[1:0], dbg_src_p[0]};
wire       p_clr = p_clr_s[1] & ~p_clr_s[2];
wire       p_idle_pc = dbg_pc >= 32'hc000158c && dbg_pc <= 32'hc0001594;
reg        p_in_idle = 1'b0, p_entered = 1'b0, p_vram_w = 1'b0;
reg [19:0] p_fclk = 20'd0, p_last = 20'd0, p_max = 20'd0, p_prev = 20'd0;
reg [15:0] p_frames = 0, p_lost = 0, p_novram = 0, p_over90 = 0;
always @(posedge clk_sys) begin
	if (p_fclk != 20'hfffff) p_fclk <= p_fclk + 20'd1;
	if (dbg_retire) begin
		if (p_idle_pc && !p_in_idle) begin p_last <= p_fclk; p_entered <= 1'b1; end
		p_in_idle <= p_idle_pc;
	end
	if (spr_we) p_vram_w <= 1'b1;
	if (vblank_irq) begin
		p_frames <= p_frames + 16'd1;
		if (p_entered && p_in_idle) begin
			p_prev <= p_last;
			if (p_last > p_max) p_max <= p_last;
			if (p_last > 20'd916790) p_over90 <= p_over90 + 16'd1;
		end else begin
			p_prev <= 20'hfffff;
			p_lost <= p_lost + 16'd1;
		end
		if (!p_vram_w) p_novram <= p_novram + 16'd1;
		p_fclk <= 20'd0; p_entered <= 1'b0; p_in_idle <= 1'b0; p_vram_w <= 1'b0;
	end
	if (p_clr) begin
		p_frames <= 16'd0; p_lost <= 16'd0; p_novram <= 16'd0; p_over90 <= 16'd0; p_max <= 20'd0;
	end
end
issp_probe #(.INSTANCE_ID("P"), .PROBE_W(128), .SOURCE_W(8)) u_issp_p (
	.clk(clk_sys),
	.probe({24'd0, p_prev, p_max, p_over90, p_novram, p_lost, p_frames}),
	.source(dbg_src_p)
);

// Instance S: sound (rtl/sound/gs_sound.sv). [15:0]/[31:16] ADPCM bytes chip 1/2 took before the bridge
// had them, [43:32]/[55:44] longest rom_ok wait (jt6295 takes the byte 243-486 clocks after the address),
// [87:56] chk_sum, [88] chk_busy. Source: bit 0 clears, bit 1 reads segment [4:2] (0-3 OKI1, 4-7 OKI2,
// 256 KB each) from SDRAM into chk_sum; scripts/oki_sum.py has the image's.
wire [7:0] dbg_src_s;
reg  [7:0] dbg_src_s1 = 8'd0, dbg_src_s2 = 8'd0, dbg_src_s3 = 8'd0;
always @(posedge clk_sys) begin dbg_src_s1 <= dbg_src_s; dbg_src_s2 <= dbg_src_s1; dbg_src_s3 <= dbg_src_s2; end
assign dbg_snd_clr   = dbg_src_s2[0] & ~dbg_src_s3[0];
assign dbg_chk_start = dbg_src_s2[1];
assign dbg_chk_seg   = dbg_src_s2[4:2];
issp_probe #(.INSTANCE_ID("S"), .PROBE_W(128), .SOURCE_W(8)) u_issp_s (
	.clk(clk_sys),
	.probe({39'd0, dbg_chk_busy, dbg_chk_sum, dbg_maxlat2, dbg_maxlat1, dbg_late2, dbg_late1}),
	.source(dbg_src_s)
);
`else
assign dbg_hold = 1'b0;
assign dbg_snd_clr = 1'b0, dbg_chk_start = 1'b0, dbg_chk_seg = 3'd0;
`endif

///////////////////////   VIDEO   ////////////////////////////////

wire vga_de_raw;
wire [7:0] crt_r, crt_g, crt_b;
wire       crt_hs, crt_vs, crt_hb, crt_vb, crt_on, crt_ce;

gs_crt u_crt (
	.clk(clk_sys), .ce(core_ce),
	.adjust(status[94] & ~forced_scandoubler),
	.hsize_idx(status[99:95]), .hpos_idx(status[106:100]), .vshift_idx(status[112:107]),
	.r_in(core_r), .g_in(core_g), .b_in(core_b),
	.hs_in(core_hs), .vs_in(core_vs), .hb_in(core_hb), .vb_in(core_vb),
	.active(crt_on), .ce_out(crt_ce),
	.r_out(crt_r), .g_out(crt_g), .b_out(crt_b),
	.hs_out(crt_hs), .vs_out(crt_vs), .hb_out(crt_hb), .vb_out(crt_vb)
);

arcade_video #(.WIDTH(320), .DW(24), .GAMMA(1)) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(crt_on ? crt_ce : core_ce),

	.RGB_in(crt_on ? {crt_r, crt_g, crt_b} : {core_r, core_g, core_b}),
	.HBlank(crt_on ? crt_hb : core_hb),
	.VBlank(crt_on ? crt_vb : core_vb),
	.HSync(crt_on ? crt_hs : core_hs),
	.VSync(crt_on ? crt_vs : core_vs),

	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
	.VGA_DE(vga_de_raw),
	.VGA_SL(VGA_SL),

	.fx(status[46:44]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

// 4:3 display (3:4 when rotated), independent of pixel aspect.
video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(VGA_VS),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),

	.VGA_DE_IN(vga_de_raw),
	.ARX((!ar) ? base_arx : (ar - 1'd1)),
	.ARY((!ar) ? base_ary : 12'd0),
	.CROP_SIZE(12'd0),
	.CROP_OFF(5'd0),
	.SCALE(status[68:66])
);

///////////////////////   DDR3   /////////////////////////////////

// The load-time client (copy, then empty-tile scan) owns the port while the game is held; in play the
// video reads and rotator writes share it (rtl/memory/gs_ddr_arb.sv). The rotator buffer is at
// 0x24000000, clear of the image at 0x30000000.
wire        rot_DDRAM_CLK, rot_DDRAM_WE, rot_DDRAM_RD, rot_busy;
wire [7:0]  rot_DDRAM_BURSTCNT, rot_DDRAM_BE;
wire [28:0] rot_DDRAM_ADDR;
wire [63:0] rot_DDRAM_DIN;
wire        ld_sel = ldr_active | et_busy;
assign DDRAM_CLK = clk_sys;
gs_ddr_arb u_ddr (
	.clk(clk_sys), .ld_sel(ld_sel),
	.ld_burst(et_busy ? et_burst : ldr_DDRAM_BURSTCNT), .ld_addr(et_busy ? et_ddr_addr : ldr_DDRAM_ADDR),
	.ld_din(ldr_DDRAM_DIN), .ld_be(ldr_DDRAM_BE), .ld_we(et_busy ? 1'b0 : ldr_DDRAM_WE),
	.ld_rd(et_busy ? et_rd : ldr_DDRAM_RD), .ld_busy(ld_busy), .ld_dv(ld_dv),
	.v_rd(v_rd), .v_addr({4'b0011, v_addr}), .v_burst(v_burst), .v_busy(v_busy), .v_dv(v_dv),
	.r_burst(rot_DDRAM_BURSTCNT), .r_addr(rot_DDRAM_ADDR), .r_din(rot_DDRAM_DIN), .r_be(rot_DDRAM_BE),
	.r_we(rot_DDRAM_WE), .r_busy(rot_busy),
	.DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR), .DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE), .DDRAM_RD(DDRAM_RD), .DDRAM_DOUT_READY(DDRAM_DOUT_READY)
);

// HDMI rotation: screen_rotate_two writes the output into DDR3 for the HPS framebuffer; the analog output keeps the
// native raster. It has no reset and counts a write as taken whenever BUSY is low (Arcade-Seta_MiSTer, Seta.sv).
screen_rotate_two screen_rotate_two
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE),

	.rotate_ccw(rotate_ccw),
	.no_rotate(~rotate_en),
	.flip(1'b0),
	.two_screen(1'b0),
	.video_rotated(),

	.FB_EN(FB_EN), .FB_FORMAT(FB_FORMAT),
	.FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE), .FB_STRIDE(FB_STRIDE),
	.FB_VBL(FB_VBL), .FB_LL(FB_LL),

	.DDRAM_CLK(rot_DDRAM_CLK),
	.DDRAM_BUSY(rot_busy),
	.DDRAM_BURSTCNT(rot_DDRAM_BURSTCNT),
	.DDRAM_ADDR(rot_DDRAM_ADDR),
	.DDRAM_DIN(rot_DDRAM_DIN),
	.DDRAM_BE(rot_DDRAM_BE),
	.DDRAM_WE(rot_DDRAM_WE),
	.DDRAM_RD(rot_DDRAM_RD)
);

endmodule
