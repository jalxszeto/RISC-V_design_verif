// Chip top level: wraps the CPU, instruction and data SRAMs, and memory
// controller, and exposes the external access port and CPU control signals.
`define functional
module chip_top(
	input logic clk_i,
	input logic rst_i,
	input logic en_cpu_i,
	input logic halt_cpu_i,
	output logic cpu_halted_o,
	
	// Crossbar Interface to memory + regfile
	input logic [13:0] addr_i,
	input logic [31:0] wdata_i,
	input logic w_en_i,
	input logic r_en_i,
	output logic [31:0] rdata_o,
	output logic rready_o

);
	// Signal Declairations
	
	logic        	isram_en;
     	logic        	isram_write_en;
     	logic 	[9:0]  	isram_addr;
     	logic 	[31:0] 	isram_wdata;
	logic 	[31:0] 	isram_rdata;
	logic 		isram_rready;
     	
	logic        	dsram_en;
     	logic        	dsram_write_en;
     	logic	[9:0]  	dsram_addr;
     	logic 	[31:0] 	dsram_wdata;
	logic 	[31:0]	dsram_rdata;
	logic		dsram_rready;
	
	logic        	core_isram_en;
     	logic 	[9:0]  	core_isram_addr;
	logic 	[31:0] 	core_isram_rdata;
     	
	logic        	core_dsram_en;
     	logic        	core_dsram_write_en;
     	logic	[9:0]  	core_dsram_addr;
     	logic 	[31:0] 	core_dsram_wdata;
	logic 	[31:0]	core_dsram_rdata;
	
    	logic [31:0] register_crossbar [0:31];
	logic cpu_enable;
	logic cpu_enable_q;
	logic next_cpu_enable;
	
	
	//
	always_comb begin
		if(cpu_enable) begin
			next_cpu_enable = (cpu_halted_o || halt_cpu_i) ? 1'b0 : 1'b1;
		end else begin
			next_cpu_enable = en_cpu_i & ~cpu_halted_o; // if CPU initiates a halt, the chip must be reset before another program can be read.
		end
	end

	always_ff @(posedge clk_i) begin
		cpu_enable <= (rst_i) ? 1'b0 : next_cpu_enable;
	end	

	always_ff @(posedge clk_i) begin
		cpu_enable_q <= (rst_i) ? 1'b0 : cpu_enable;
	end

	cpu_top cpu (
		.clk_i(clk_i),
		.rst_i(rst_i),
		.en_i(cpu_enable_q),
		.halted_o(cpu_halted_o),
		.reg_crossbar_o(register_crossbar),	
    		.isram_en_o(core_isram_en),
    		.isram_addr_o(core_isram_addr),
    		.isram_rdata_i(core_isram_rdata),
		.isram_rready_i(core_isram_rready),
		.dsram_en_o(core_dsram_en),
    		.dsram_write_en_o(core_dsram_write_en),
    		.dsram_addr_o(core_dsram_addr),
    		.dsram_wdata_o(core_dsram_wdata),
    		.dsram_rdata_i(core_dsram_rdata),
		.dsram_rready_i(core_dsram_rready)
	);
	
	
	sram_wrapper data_memory (
    		.clk_i(clk_i),
    		.rst_i(rst_i),
    		.en_i(dsram_en),
    		.write_en_i(dsram_write_en),
    		.addr_i(dsram_addr),
    		.wdata_i(dsram_wdata),
    		.rdata_o(dsram_rdata),
		.rready_o(dsram_rready)
	);

	sram_wrapper instruction_memory (
    		.clk_i(clk_i),
    		.rst_i(rst_i),
    		.en_i(isram_en),
    		.write_en_i(isram_write_en),
    		.addr_i(isram_addr),
    		.wdata_i(isram_wdata),
    		.rdata_o(isram_rdata),
		.rready_o(isram_rready)
	);

	memory_controller mem_ctrl (
		.cpu_enabled_d_i(cpu_enable), // fix started fetch bubble
		.cpu_enabled_q_i(cpu_enable_q),
		.core_isram_en_i(core_isram_en),
     		.core_isram_addr_i(core_isram_addr),
		.core_isram_rdata_o(core_isram_rdata),
		.core_isram_rready_o(core_isram_rready),
		.core_dsram_en_i(core_dsram_en),
     		.core_dsram_write_en_i(core_dsram_write_en),
     		.core_dsram_addr_i(core_dsram_addr),
     		.core_dsram_wdata_i(core_dsram_wdata),
		.core_dsram_rdata_o(core_dsram_rdata),
		.core_dsram_rready_o(core_dsram_rready),
		.addr_i(addr_i),
		.wdata_i(wdata_i),
		.w_en_i(w_en_i),
		.r_en_i(r_en_i),
		.rdata_o(rdata_o),
		.rready_o(rready_o),
		.isram_en_o(isram_en),
     		.isram_write_en_o(isram_write_en),
     		.isram_addr_o(isram_addr),
     		.isram_wdata_o(isram_wdata),
		.isram_rdata_i(isram_rdata),
		.isram_rready_i(isram_rready),
		.dsram_en_o(dsram_en),
     		.dsram_write_en_o(dsram_write_en),
     		.dsram_addr_o(dsram_addr),
     		.dsram_wdata_o(dsram_wdata),
		.dsram_rdata_i(dsram_rdata),
		.dsram_rready_i(dsram_rready),
		.register_crossbar_i(register_crossbar)
	);
		
endmodule
