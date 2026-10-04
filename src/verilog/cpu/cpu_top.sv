// Top level of the RISC-V CPU core. Connects fetch, decode, execute, and the
// register file, and handles load stalls, data SRAM accesses, and ebreak halt.

module cpu_top (
	input logic clk_i,
	input logic rst_i,
	input logic en_i,
	
	output logic halted_o,
	
	output logic [31:0] reg_crossbar_o [0:31],
	
	output logic 	    isram_en_o,
	output logic [9:0]  isram_addr_o,
	input  logic [31:0] isram_rdata_i,
	input  logic 	    isram_rready_i,

	output logic 		dsram_en_o,
	output logic 		dsram_write_en_o,
	output logic [9:0]  dsram_addr_o,
    output logic [31:0] dsram_wdata_o,
	input  logic [31:0] dsram_rdata_i,
	input  logic 	    dsram_rready_i	

);
	
	import cpu_pkg::*;
	
	// === Signal Declarations === //
	logic stall_core;



	logic [4:0] rs1_addr;
	logic [4:0] rs2_addr;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    logic rd_write_en;
    logic [4:0]  rd_addr;
    logic [31:0] rd_data;
	
	logic [31:0] reg_values [0:31];

	instr_type_e instr_type;
	logic [31:0] imm;
	
	logic [31:0] prev_pc;

	logic new_instr;



	// Fetch
	logic [31:0] instr;	
	logic [31:0] current_pc;
	logic instr_vld;
	logic branch_vld;
	logic [9:0] branch_trgt;	
	logic branch_taken;



	always_ff @(posedge clk_i) begin
		prev_pc <= current_pc;
	end

	assign new_instr = (prev_pc != current_pc); // Whether cycle has completed after new instruction fetched
	

	assign stall_core = halted_o | ~en_i | (instr_type == LOAD & ~(dsram_rready_i & ~new_instr)); // When load, wait for memory to respond and wait until next cycle for dsram_rdata_i updates



	// === Instruction Fetch === //
	fetch u_fetch (
		.clk_i(clk_i),
		.rst_i(rst_i),
		.en_i(en_i),
		.stall_core_i(stall_core),
		.isram_en_o(isram_en_o),
		.isram_addr_o(isram_addr_o),
		.isram_rdata_i(isram_rdata_i),
		.isram_rready_i(isram_rready_i),
		.instr_o(instr),
		.pc_o(current_pc),
		.instr_vld_o(instr_vld),
		.branch_vld_i(branch_vld),
		.branch_trgt_i(branch_trgt),
		.branch_taken_i(branch_taken)
	);	

	

	


	// Halt when ebreak is valid
	always_comb begin
		halted_o = (instr_vld & instr_type == EBREAK);
	end

	// Data SRAM access for loads and stores
    assign dsram_en_o       = (instr_type inside {LOAD, STORE});
    assign dsram_write_en_o = (instr_type == STORE);
    assign dsram_addr_o     = rd_data[11:2];
    assign dsram_wdata_o    = rs2_data;



	// Register file (write-back selects load data for lw)
	reg_file rf (clk_i, rst_i, rs1_addr, rs2_addr, rs1_data, rs2_data, rd_write_en, rd_addr, instr_type == LOAD ? dsram_rdata_i : rd_data, reg_values);

	// Expose register values to the external port
	assign reg_crossbar_o = reg_values;



	// Decode instruction
	decode u_decode (
		instr,
		instr_type,
		rs1_addr,
		rs2_addr,
		rd_addr,
		imm
	);

	execute u_execute (
		instr_type,
		rs1_data,
		rs2_data,
		imm,
		current_pc,
		rd_data,
		branch_vld,
		branch_trgt,
		branch_taken
	);

	// Whether instruction should write result back to register
	assign rd_write_en = instr_type inside {ADD, SUB, ADDI, SLL, SRL, LOAD};

endmodule
