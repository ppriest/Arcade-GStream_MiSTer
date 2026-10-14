// SPDX-License-Identifier: GPL-3.0-or-later
// Bench top: gs_et_scan alone; main.cpp answers its DDR3 bursts from the image and checks the table it writes.
module tb_et (
	input             clk,
	input             start,
	output            busy,
	output            rd,
	output     [28:0] addr,
	output      [7:0] burst,
	input             ddr_busy,
	input             dv,
	input      [63:0] dout,
	output            et_we,
	output     [12:0] et_addr,
	output      [7:0] et_data
);
gs_et_scan u_et (.*);
endmodule
