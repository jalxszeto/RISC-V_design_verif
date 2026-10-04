// Arbitrates SRAM ownership between the CPU and the external port, and routes
// external accesses to instruction SRAM, data SRAM, or the register file.
module memory_controller (
	input logic cpu_enabled_d_i, // is the cpu currently executing a program an needs access to the sram?
	input logic cpu_enabled_q_i,	
	// CPU Memory Access Port (isram RO, dsram RW)
	input logic        	core_isram_en_i,
     	input logic 	[9:0]  	core_isram_addr_i,
	output logic 	[31:0] 	core_isram_rdata_o,
	output logic 		core_isram_rready_o,
     	
	input logic        	core_dsram_en_i,
     	input logic        	core_dsram_write_en_i,
     	input logic	[9:0]  	core_dsram_addr_i,
     	input logic 	[31:0] 	core_dsram_wdata_i,
	output logic 	[31:0]	core_dsram_rdata_o,
	output logic 		core_dsram_rready_o,

	// External Access Port
		
	input logic 	[13:0] 	addr_i,
	input logic 	[31:0] 	wdata_i,
	input logic 		w_en_i,
	input logic 		r_en_i,
	output logic 	[31:0] 	rdata_o,
	output logic 		rready_o,

	// === Output Interface to Memories === //	
	
	output logic        	isram_en_o,
     	output logic        	isram_write_en_o,
     	output logic 	[9:0]  	isram_addr_o,
     	output logic 	[31:0] 	isram_wdata_o,
	input logic 	[31:0] 	isram_rdata_i,
	input logic 		isram_rready_i,
     	
	output logic        	dsram_en_o,
     	output logic        	dsram_write_en_o,
     	output logic	[9:0]  	dsram_addr_o,
     	output logic 	[31:0] 	dsram_wdata_o,
	input logic 	[31:0]	dsram_rdata_i,
	input logic 		dsram_rready_i,
	
	input [31:0]		register_crossbar_i [0:31]	

);
	always_comb begin
		// Default Values
	        isram_en_o 		= '0;
     	        isram_write_en_o 	= '0;
     	 	isram_addr_o 		= '0;
     	 	isram_wdata_o 		= '0;
	 	core_isram_rdata_o 	= '0;  
	 	core_isram_rready_o	= '0;
	        dsram_en_o 		= '0;
     	        dsram_write_en_o 	= '0;
     		dsram_addr_o 		= '0;
     	 	dsram_wdata_o 		= '0;
	        core_dsram_rdata_o      = '0;
	        core_dsram_rready_o   	= '0;
		rdata_o			= '0;
		rready_o		= '0;
		
		if (cpu_enabled_d_i && !cpu_enabled_q_i) begin
			// Set Instruction Pointer before enabling the core
	        	isram_en_o 		= 1'b1;
     	        	isram_write_en_o 	= 1'b0;
     	 	  	isram_addr_o 		= '0;
     	 	 	isram_wdata_o 		= '0;

		end else if(cpu_enabled_q_i) begin
			// Provide the CPU with RO access to the isram and RW
			// access to the dsram
	        	isram_en_o 		= core_isram_en_i;
     	        	isram_write_en_o 	= 1'b0;
     	 	  	isram_addr_o 		= core_isram_addr_i;
     	 	 	isram_wdata_o 		= '0;
	 	 	core_isram_rdata_o 	= isram_rdata_i;  
	 		core_isram_rready_o	= isram_rready_i;
     	
	        	dsram_en_o 		= core_dsram_en_i;
     	        	dsram_write_en_o 	= core_dsram_write_en_i;
     		  	dsram_addr_o 		= core_dsram_addr_i;
     	 	 	dsram_wdata_o 		= core_dsram_wdata_i;
	 		core_dsram_rdata_o      = dsram_rdata_i;
	 		core_dsram_rready_o   	= dsram_rready_i;
	
	
		end else begin
			case(addr_i[13:12])
				2'b00: begin // Instruction-SRAM Memory Access
					
	        			isram_en_o       = (w_en_i || r_en_i);
     	        			isram_write_en_o = w_en_i;
     	 	  			isram_addr_o 	 = addr_i[11:2];
     	 	 			isram_wdata_o 	 = wdata_i;
	 	 			rdata_o 	 = isram_rdata_i;  
	 				rready_o	 = isram_rready_i;
				end 
				2'b01: begin // Data-SRAM Memory Access
					
	        			dsram_en_o 	 = (w_en_i || r_en_i);
     	        			dsram_write_en_o = w_en_i;
     		  			dsram_addr_o 	 = addr_i[11:2];
     	 	 			dsram_wdata_o 	 = wdata_i;
	 				rdata_o     	 = dsram_rdata_i;
	 				rready_o   	 = dsram_rready_i;
	
				end
				2'b10: begin // Register File Access
					rdata_o = (r_en_i) ? register_crossbar_i[addr_i[6:2]] : '0;
					rready_o = r_en_i;
				end
			
			endcase
		end
	end 



endmodule
