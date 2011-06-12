/*
*
* Copyright (c) 2011 fpgaminer@bitcoin-mining.com
*
*
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
* 
*/


`timescale 1ns/1ps
//
// Altera-specific top level module
//
module fpgaminer_top_altera (
	input osc_clk;
);

	// The LOOP_LOG2 parameter determines how unrolled the SHA-256
	// calculations are. For example, a setting of 1 will completely
	// unroll the calculations, resulting in 128 rounds and a large, fast
	// design.
	//
	// A setting of 2 will result in 64 rounds, with half the size and
	// half the speed. 3 will be 32 rounds, with 1/4th the size and speed.
	// And so on.
	//
	// Valid range: [0, 5]
`ifdef CONFIG_LOOP_LOG2
	localparam LOOP_LOG2 = `CONFIG_LOOP_LOG2;
`else
	localparam LOOP_LOG2 = 0;
`endif

// The MERGE_LKOG2 parameter determines how many SHA-256 stages to combine
// into one pipe stage.
// A value of 1 is the default and is the same as the normal behavior
// Using a larger value will cause a clock speed drop, but on the other hand,
// it will require less clock cycles and less pipe registers.
`ifdef CONFIG_MERGE_LOG2
	localparam MERGE_LOG2 = `CONFIG_MERGE_LOG2;
`else
	localparam MERGE_LOG2 = 0;
`endif

	//// PLL
	wire hash_clk;
	main_pll pll_blk (osc_clk, hash_clk);

	//// Virtual Wire Control
	wire [255:0] midstate_vw;
	wire  [95:0] data2_vw;
	wire  [31:0] golden_nonce

	virtual_wire # (.PROBE_WIDTH(0),  .WIDTH(256), .INSTANCE_ID("STAT")) midstate_vw_blk     (.probe(), .source(midstate_vw));
	virtual_wire # (.PROBE_WIDTH(0),  .WIDTH(96),  .INSTANCE_ID("DAT2")) data2_vw_blk        (.probe(), .source(data2_vw));
	virtual_wire # (.PROBE_WIDTH(32), .WIDTH(0),   .INSTANCE_ID("GNON")) golden_nonce_vw_blk (.probe(golden_nonce), .source());
`ifdef USE_NONC
	// I use this for tracking progress, not needed for useful work
	virtual_wire # (.PROBE_WIDTH(32), .WIDTH(0),   .INSTANCE_ID("NONC")) nonce_vw_blk        (.probe(nonce),        .source());
`endif

	fpgaminer_core #(
		.LOOP_LOG2(LOOP_LOG2),
		.MERGE_LOG2(MERGE_LOG2)
	) core (
		.clk(hash_clk),
		.reset(1'b0),
		.midstate_in(midstate_vw),
		.data_in(data2_vw),
		.hash2_valid(),
		.hash2(),
		.golden_nonce(golden_nonce)
	);

endmodule

