// 32 x 32-bit RISC-V integer register file.
// Register x0 always reads as zero and ignores writes.
module reg_file (
    input  logic        clk_i,
    input  logic        rst_i,

    input  logic [4:0]  rs1_addr_i, //Register Source 1 Address Input
    input  logic [4:0]  rs2_addr_i,
    output logic [31:0] rs1_data_o,
    output logic [31:0] rs2_data_o, //Register Source 2 Data Output

    input  logic        rd_write_en_i, //Register Destination Write Enable Input
    input  logic [4:0]  rd_addr_i,
    input  logic [31:0] rd_data_i,

    // Read-only architectural state exposed to the debug crossbar.
    output logic [31:0] reg_values_o [0:31] //Register Values Output
);

    logic [31:0] registers [0:31];
    integer i; //used for generate loops in systemverilog

    always_comb begin
        rs1_data_o = (rs1_addr_i == 5'd0) ? 32'd0 : registers[rs1_addr_i];
        rs2_data_o = (rs2_addr_i == 5'd0) ? 32'd0 : registers[rs2_addr_i];
    end

    assign reg_values_o[0] = 32'd0;
    generate
        for (genvar register_index = 1;
             register_index < 32;
             register_index++) begin : gen_debug_register_values
            assign reg_values_o[register_index] = registers[register_index];
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end else if (rd_write_en_i && (rd_addr_i != 5'd0)) begin
            registers[rd_addr_i] <= rd_data_i;
        end
    end

endmodule
