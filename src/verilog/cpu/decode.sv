// Decodes a 32-bit RISC-V instruction into its type, register addresses, and
// sign-extended immediate.

import cpu_pkg::*;

module decode (
    input logic [31:0] instr,

    output instr_type_e instr_type,
    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic [4:0] rd,
    output logic [31:0] imm
);


    logic funct7;
    logic [2:0] funct3;
    logic [6:0] opcode;

    always_comb begin
        // Extract components from instruction
        funct7 = instr[30]; // Only bit 30 differentiates ADD and SUB
        rs2 = instr[24:20];
        rs1 = instr[19:15];
        funct3 = instr[14:12];
        rd = instr[11:7];
        opcode = instr[6:0];

        imm = 32'b0; // Default assignment
        
        // Set instruction type
        case (opcode)
            // Opcodes independent of funct3 or funct7
            7'b0010011: instr_type = ADDI;
            7'b0000011: instr_type = LOAD;
            7'b0100011: instr_type = STORE;
            7'b1100011: instr_type = BEQ;
            7'b1110011: instr_type = EBREAK; // Using binary representation of 32'h00100073

            7'b0110011: case (funct3) 
                // Opcodes dependent on funct3 only
                3'b001: instr_type = SLL;
                3'b101: instr_type = SRL;

                3'b000: case (funct7) 
                    // Opcodes dependent on funct7
                    1'b0: instr_type = ADD;
                    1'b1: instr_type = SUB;
                endcase
                default: instr_type = NOP;

            endcase
            default: instr_type = NOP;

        endcase

        // Extract imm
        case (opcode)
            // I-type instructions
            7'b0010011, 7'b0000011: imm = {{20{instr[31]}}, instr[31:20]}; // Sign extension

            // S-type
            7'b0100011: imm = {{20{instr[31]}}, {instr[31:25], instr[11:7]}};

            // B-type
            7'b1100011: imm = {{19{instr[31]}}, {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}};
            default: imm = 32'b0;
        endcase

    end

endmodule