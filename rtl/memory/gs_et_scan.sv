// SPDX-License-Identifier: GPL-3.0-or-later
// The empty-sprite-tile table, built at load time: the image's sprite tiles (16 MB from BASE in DDR3, 65,536 tiles of
// 256 bytes) are read one 32-beat burst a tile, and bit k of byte a is set when tile 8a + k has no non-zero byte.
// gs_video skips those tiles' rows (an empty tile draws nothing). Up to four bursts in flight; the data comes back in
// order. About 2.1 million beats: some 35 ms at 60.75 MHz.

module gs_et_scan #(
	parameter [27:0] BASE = 28'h0500000          // SD_SPR, a byte offset in the DDR3 image
) (
	input             clk,
	input             start,                     // pulse
	output reg        busy = 1'b0,

	// DDR3 (through gs_ddr_arb's ld port): Avalon, a burst held until a clock without busy
	output reg        rd = 1'b0,
	output     [28:0] addr,
	output      [7:0] burst,
	input             ddr_busy,
	input             dv,
	input      [63:0] dout,

	output reg        et_we = 1'b0,
	output reg [12:0] et_addr,
	output reg  [7:0] et_data
);

reg  [16:0] issued;                              // tiles requested
reg  [16:0] done;                                // tiles whose 32 beats have arrived
reg  [4:0]  bt;
reg         nz;
reg  [7:0]  bits;
reg  [16:0] a_tile;
assign addr  = {4'b0011, BASE[27:3] + {a_tile[15:0], 5'd0}};
assign burst = 8'd32;
wire        room = issued - done < 17'd4;

always @(posedge clk) begin
	et_we <= 1'b0;
	if (start) begin
		busy <= 1'b1; issued <= 17'd0; done <= 17'd0; bt <= 5'd0; nz <= 1'b0; rd <= 1'b0;
	end else if (busy) begin
		if (rd && !ddr_busy) begin
			rd <= 1'b0;
			issued <= issued + 17'd1;
		end else if (!rd && issued != 17'h10000 && room) begin
			rd <= 1'b1;
			a_tile <= issued;
		end
		if (dv) begin
			bt <= bt + 5'd1;
			if (bt == 5'd31) begin
				bits <= {dout == 64'd0 && !nz, bits[7:1]};
				nz <= 1'b0;
				if (done[2:0] == 3'd7) begin
					et_we <= 1'b1;
					et_addr <= done[15:3];
					et_data <= {dout == 64'd0 && !nz, bits[7:1]};
				end
				done <= done + 17'd1;
				if (done == 17'hffff) busy <= 1'b0;
			end else if (dout != 64'd0) nz <= 1'b1;
		end
	end
end

endmodule
