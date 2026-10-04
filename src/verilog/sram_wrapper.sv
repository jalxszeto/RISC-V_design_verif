// Read/write data memory wrapper around SRAM macro.
module sram_wrapper (
    input  logic        clk_i,
    input  logic        rst_i,	
    input  logic        en_i,
    input  logic        write_en_i,
    input  logic [9:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic 	rready_o
);

    	CF_SRAM_1024x32_macro u_sram (
    	    .DO        (rdata_o),
    	    .DI        (wdata_i),
    	    .AD        (addr_i),
    	    .CLKin     (clk_i),
    	    .EN        (en_i),
    	    .R_WB      (~write_en_i),
    	    .BEN       (32'hFFFF_FFFF),
    	    .TM        (1'b0),
    	    .SM        (1'b0),
    	    .WLBI      (1'b0),
    	    .WLOFF     (1'b0),
    	    .ScanInCC  (1'b0),
    	    .ScanInDL  (1'b0),
    	    .ScanInDR  (1'b0),
    	    .ScanOutCC (),
    	    .vpwrac    (1'b1),
    	    .vpwrpc    (1'b1)
    	);
	

	logic rdata_valid;

	always_ff @(posedge clk_i) begin
		if(rst_i) begin
			rdata_valid <= 1'b0;
		end else begin
			rdata_valid <= en_i;
		end
	end

	assign rready_o = rdata_valid;

endmodule
