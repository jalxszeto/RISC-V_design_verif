// Execute stage: computes ALU results, memory addresses, and branch decisions
// and targets for the decoded instruction.

import cpu_pkg::*;

module execute (
    input instr_type_e instr_type,
    input logic [31:0] rs1_data,
    input logic [31:0] rs2_data,
    input logic [31:0] imm,
    input logic [31:0] current_pc,

    output logic [31:0] rd_data,
    output logic branch_vld,
    output logic [9:0] branch_trgt,
    output logic branch_taken
);

logic [31:0] branch_trgt_full;
always_comb begin
    rd_data = 32'b0;
    branch_vld = 1'b0;
    branch_trgt = 10'b0;
    branch_taken = 1'b0;
    
    // Evaluate based on instruction
    case (instr_type)
        ADD: rd_data = rs1_data + rs2_data;
        SUB: rd_data = rs1_data - rs2_data;
        ADDI: rd_data = rs1_data + imm;
        SLL: rd_data = rs1_data << rs2_data[4:0];
        SRL: rd_data = rs1_data >> rs2_data[4:0];
        LOAD, STORE: rd_data = rs1_data + imm;
        BEQ: begin
            branch_vld = 1'b1;
            branch_taken = (rs1_data == rs2_data);

            branch_trgt_full = current_pc + imm;
            branch_trgt = branch_trgt_full[11:2];
        end
    endcase
end
endmodule