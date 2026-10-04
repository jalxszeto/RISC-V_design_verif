// Instruction fetch stage: holds the program counter, reads instructions from
// instruction SRAM, and selects the next PC (sequential, branch target, or stall).
module fetch (
	input logic clk_i,
	input logic rst_i,
	input logic en_i,

	input logic stall_core_i,
	
	// === Instruction RAM Interface === //
	output logic isram_en_o,
	output logic [9:0] isram_addr_o,
	input logic [31:0] isram_rdata_i,
	input logic isram_rready_i,


	// === Fetched Instruction === //
	output logic [31:0] instr_o,
	output logic [31:0] pc_o, //current instruction 
	output logic instr_vld_o,

	input logic branch_vld_i,
	input logic [9:0] branch_trgt_i,
	input logic branch_taken_i
);


	logic [31:0] next_pc; //instruction to be run at the next cycle
	
	always_ff @(posedge clk_i) begin
		if(rst_i) begin
			pc_o <= '0;
		end else if(en_i & !stall_core_i) begin
			pc_o <= next_pc;
		end
	end

	always_comb begin
		next_pc 	= '0;
		isram_en_o 	= '0;
		isram_addr_o	= '0;
		instr_o 	= '0;
		instr_vld_o	= '0;
		if(en_i) begin
			if (stall_core_i) begin
				next_pc = pc_o; //when we stall we stay at the same instruction at the next cycle
			end else if (branch_vld_i && branch_taken_i) begin
				next_pc = {20'b0, branch_trgt_i, 2'b00};
			end else begin
				next_pc = pc_o + 4;
			end

			isram_en_o = 1'b1;
			isram_addr_o = next_pc[11:2];
			instr_o = isram_rdata_i;
			instr_vld_o = isram_rready_i;

		end
	end

endmodule
