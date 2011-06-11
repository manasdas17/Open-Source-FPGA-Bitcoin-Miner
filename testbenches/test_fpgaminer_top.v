// Testbench for fpgaminer_top.v
// TODO: Expand and generalize to test any mining core or complete design.
//


`timescale 1ns/1ps

module test_fpgaminer_top ();

	reg clk;
	reg reset;
	reg [31:0] cycle;
	wire [31:0]golden_nonce;
	wire [31:0]nonce_adjust;
	wire [255:0] hash2;

	fpgaminer_core #(
		.LOOP_LOG2(0),
		.MERGE_LOG2(0)
	) uut (
		.clk(clk),
		.reset(reset),
		.midstate_in(256'h228ea4732a3c9ba860c009cda7252b9161a5e75ec8c582a5f106abb3af41f790),
		.data_in(96'h2194261a9395e64dbed17115),
		.hash2(hash2),
		.golden_nonce(golden_nonce),
		.nonce_adjust(nonce_adjust)
	);



	initial begin
		$dumpfile("fpgaminer.vcd");
		$dumpvars(0,test_fpgaminer_top);
		clk = 0;
		cycle = 32'd0;
		#2 reset = 1;
		repeat(130)
		begin
			#5 clk = 1;
			#5 clk = 0;
		end
		#5 clk = 1;
		#2 reset = 0;
		#3 clk = 0;
		

		// Test data
		uut.nonce = 32'h0e33337a - 256;	// Minus a little so we can exercise the code a bit

		repeat(280)
		begin
			#5 clk = 1;
			#5 clk = 0;
			$display ("cycle: %8x, nonce_adjust: %8x, golden_nonce: %8x hash2: %256x", cycle, nonce_adjust, golden_nonce, hash2);
		end
	end


	always @ (posedge clk)
	begin
		cycle <= cycle + 32'd1;
	end

endmodule

