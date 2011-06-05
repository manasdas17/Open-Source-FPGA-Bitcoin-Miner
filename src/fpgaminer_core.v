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
// Generic top level module
//
module fpgaminer_core #(
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
	parameter LOOP_LOG2=0,
	// The MERGE_LKOG2 parameter determines how many SHA-256 stages to combine
	// into one pipe stage.
	// A value of 1 is the default and is the same as the normal behavior
	// Using a larger value will cause a clock speed drop, but on the other hand,
	// it will require less clock cycles and less pipe registers.
	parameter MERGE_LOG2=0
) (
	input clk,
	input reset,
	input [255:0] midstate_in,
	input [95:0] data_in,
	output hash2_valid,
	output [255:0] hash2,
	output [31:0] golden_nonce,
	output [31:0] nonce_adjust
);
	// No need to adjust these parameters
	localparam [5:0] LOOP = (6'd1 << LOOP_LOG2);
	localparam [5:0] MERGE = (6'd1 << MERGE_LOG2);

	// The nonce will always be larger at the time we discover a valid
	// hash. This is its offset from the nonce that gave rise to the valid
	// hash (except when LOOP_LOG2 == 0 or 1, where the offset is 131 or
	// 66 respectively).
	localparam [31:0] GOLDEN_NONCE_OFFSET = (32'd1 << (7 - LOOP_LOG2)) + 32'd1;

	reg [255:0] state ;
	reg [127:0] data;
	reg [31:0] nonce;


	//// Hashers
	reg [31:0] golden_nonce ;
	wire [255:0] hash, hash2;
	reg [5:0] cnt = 6'd0;
	reg feedback = 1'b0;

	sha256_transform #(.LOOP(LOOP), .MERGE(MERGE)) uut (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(state),
		.rx_input({384'h000002800000000000000000000000000000000000000000000000000000000000000000000000000000000080000000, data}),
		.tx_hash(hash)
	);
	sha256_transform #(.LOOP(LOOP), .MERGE(MERGE)) uut2 (
		.clk(hash_clk),
		.feedback(feedback),
		.cnt(cnt),
		.rx_state(256'h5be0cd191f83d9ab9b05688c510e527fa54ff53a3c6ef372bb67ae856a09e667),
		.rx_input({256'h0000010000000000000000000000000000000000000000000000000080000000, hash}),
		.tx_hash(hash2)
	);

	//// Control Unit
	wire is_golden_ticket;
	reg feedback_d1;
	wire [5:0] cnt_next;
	wire [31:0] nonce_next;
	wire feedback_next;

	assign cnt_next =  reset ? 6'd0 : (cnt + MERGE) & ((LOOP*MERGE)-6'd1);
	// On the first count (cnt==0), load data from previous stage (no feedback)
	// otherwise, take feedback from current stage
	// This reduces the throughput by a factor of (LOOP), but also reduces the design size by the same amount
	assign feedback_next = (cnt_next != 6'd0);
	assign nonce_next =
		reset ? 32'd0 :
		feedback_next ? nonce : (nonce + 32'd1);

	assign nonce_adjust = nonce - 128/(LOOP*MERGE) - 1;
	assign is_golden_ticket = (hash2[255:224] == 32'h00000000) && hash2_valid;
	
	always @ (posedge hash_clk)
	begin
		cnt <= cnt_next;
		feedback <= feedback_next;
		hash2_valid <= ~feedback;

		// Give new data to the hasher
		state <= midstate_in;
		data <= {nonce_next, data_in};
		nonce <= nonce_next;

		// Check to see if the last hash generated is valid.
		golden_nonce <= reset ? 32'b0 : is_golden_ticket ? nonce_adjust : golden_nonce;
	end

endmodule

