/*
 * File `cpu_ref_model.svh`
 *
 * The golden model: a small instruction set simulator for the 
 * RV32I that the DUT implements. It executes a program one
 * instruction at a time without taking up simulation time
 *
 * Predicts:
 *   The architectural register state the CPU should end up with,
 *   The data memory contents the CPU should end up with, and
 *   The exact sequence of stores the CPU should perform.
 *
 * The scoreboard instantiates a ref_model and compares the DUT against it.
 * Because the model is architectural, it works no matter how many
 * cycles the CPU takes or how it is pipelined - the only thing
 * it assumes is that stores reach memory in program order.
 */
class cpu_ref_model;

    logic [31:0] regs [REG_COUNT];
    logic [31:0] imem [ISRAM_WORDS];
    logic [31:0] dmem [DSRAM_WORDS];

    logic [31:0] pc;
    bit halted;                   // The model reached ebreak
    bit timed_out;                // The instruction bound ended before ebreak
    int instr_retired;            // Number of instructions executed so far

    // Every store the program performs, in order. The scoreboard pops
    // one of these each time it sees the CPU write data memory.
    ref_store_t store_queue [$];

    // Set to 1 to print every retired instruction (+REF_TRACE plusarg)
    bit trace;    // Optional per-instruction logging switch

    // Constructor
    function new();
        trace = 1'b0;
        clear_state();
        foreach (imem[i]) begin
            imem[i] = EBREAK_WORD;
        end
        foreach (dmem[i]) begin
            dmem[i] = '0;
        end
    endfunction: new

    // Memory image maintenance: the scoreboard keeps these in step
    // with everything it sees written into the DUT
    function void write_imem(input logic [9:0] index, input logic [31:0] value);
        imem[index] = value;
    endfunction: write_imem

    function void write_dmem(input logic [9:0] index, input logic [31:0] value);
        dmem[index] = value;
    endfunction: write_dmem

    function void load_dmem(const ref logic [31:0] image [DSRAM_WORDS]);
        foreach (dmem[i]) begin
            dmem[i] = image[i];
        end
    endfunction: load_dmem

    function void load_imem(const ref logic [31:0] image [ISRAM_WORDS]);
        foreach (imem[i]) begin
            imem[i] = image[i];
        end
    endfunction: load_imem

    // Reset architectural registers, program counter, and trace queues
    function void clear_state();
        foreach (regs[i]) begin
            regs[i] = '0;
        end
        pc            = '0;
        halted        = 1'b0;
        timed_out     = 1'b0;
        instr_retired = 0;
        store_queue.delete();
    endfunction: clear_state

    // Execute from reset until the program halts on ebreak, or until
    // max_instr instructions have retired (indicating an infinite loop)
    function void run(input int max_instr);
        clear_state();
        while (!halted && instr_retired < max_instr) begin
            step();
        end
        if (!halted) begin
            timed_out = 1'b1;
            $error($stime, " Ref: reference model did not halt after %0d instructions\n", max_instr);
        end
    endfunction: run

    // Execute exactly one instruction from instruction memory
    function void step();
        logic [31:0] instr;
        logic [31:0] next_pc;
        logic [6:0]  opcode;
        logic [2:0]  funct3;
        logic [6:0]  funct7;
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [4:0]  rd;
        logic [31:0] rs1_val;
        logic [31:0] rs2_val;
        logic [31:0] imm_i;
        logic [31:0] imm_s;
        logic [31:0] imm_b;
        logic [31:0] byte_addr;
        logic [9:0]  word_addr;
        logic [31:0] result;
        bit          write_rd;
        bit          branch_taken;
        string       text;

        instr   = imem[pc[11:2]];
        next_pc = pc + 32'd4;

        opcode  = instr[6:0];
        funct3  = instr[14:12];
        funct7  = instr[31:25];
        rs1     = instr[19:15];
        rs2     = instr[24:20];
        rd      = instr[11:7];

        rs1_val = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
        rs2_val = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

        imm_i   = {{20{instr[31]}}, instr[31:20]};
        imm_s   = {{20{instr[31]}}, instr[31:25], instr[11:7]};
        imm_b   = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};

        result       = '0;
        write_rd     = 1'b0;
        branch_taken = 1'b0;
        text         = "nop";

        case (opcode)
            // R-type: add / sub / sll / srl
            7'b0110011: begin
                case ({funct7, funct3})
                    {7'b0000000, 3'b000}: begin
                        result   = rs1_val + rs2_val;
                        write_rd = 1'b1;
                        text     = $sformatf("add  x%0d, x%0d, x%0d", rd, rs1, rs2);
                    end
                    {7'b0100000, 3'b000}: begin
                        result   = rs1_val - rs2_val;
                        write_rd = 1'b1;
                        text     = $sformatf("sub  x%0d, x%0d, x%0d", rd, rs1, rs2);
                    end
                    // The shift amount is the low 5 bits of rs2, per the ISA:
                    // "SLL, SRL and SRA perform shifts on the value in register
                    // rs1 by the shift amount held in the lower 5 bits of rs2"
                    {7'b0000000, 3'b001}: begin
                        result   = rs1_val << rs2_val[4:0];
                        write_rd = 1'b1;
                        text     = $sformatf("sll  x%0d, x%0d, x%0d", rd, rs1, rs2);
                    end
                    {7'b0000000, 3'b101}: begin
                        result   = rs1_val >> rs2_val[4:0];
                        write_rd = 1'b1;
                        text     = $sformatf("srl  x%0d, x%0d, x%0d", rd, rs1, rs2);
                    end
                    default: ; // not implemented by this DUT: behaves as a nop
                endcase
            end

            // I-type: addi
            7'b0010011: begin
                if (funct3 == 3'b000) begin
                    result   = rs1_val + imm_i;
                    write_rd = 1'b1;
                    text     = $sformatf("addi x%0d, x%0d, %0d", rd, rs1, $signed(imm_i));
                end
            end

            // Load word
            7'b0000011: begin
                if (funct3 == 3'b010) begin
                    byte_addr = rs1_val + imm_i;
                    word_addr = byte_addr[11:2];
                    result    = dmem[word_addr];
                    write_rd  = 1'b1;
                    text      = $sformatf("lw   x%0d, %0d(x%0d)  [dmem[0x%0x] = 0x%08x]",
                                          rd, $signed(imm_i), rs1, word_addr, result);
                end
            end

            // Store word
            7'b0100011: begin
                if (funct3 == 3'b010) begin
                    ref_store_t st;

                    byte_addr        = rs1_val + imm_s;
                    word_addr        = byte_addr[11:2];
                    dmem[word_addr]  = rs2_val;
                    st.addr          = word_addr;
                    st.data          = rs2_val;
                    store_queue.push_back(st);
                    text = $sformatf("sw   x%0d, %0d(x%0d)  [dmem[0x%0x] <= 0x%08x]",
                                     rs2, $signed(imm_s), rs1, word_addr, rs2_val);
                end
            end

            // Branch if equal:
            // The DUT truncates the branch target to the 4 KB instruction
            // memory (branch_trgt is alu_out[11:2]), so the model does the
            // same thing
            7'b1100011: begin
                if (funct3 == 3'b000) begin
                    branch_taken = (rs1_val == rs2_val);
                    if (branch_taken) begin
                        next_pc = (pc + imm_b) & 32'h0000_0FFC;
                    end
                    text = $sformatf("beq  x%0d, x%0d, %0d  [%s]",
                                     rs1, rs2, $signed(imm_b),
                                     (rs1_val == rs2_val) ? "taken" : "not taken");
                end
            end

            // ebreak - stop the CPU
            7'b1110011: begin
                if (funct3 == 3'b000) begin
                    halted = 1'b1;
                    if (trace) begin
                        $display($stime, " Ref: pc 0x%03x  ebreak (halt after %0d instructions)\n",
                                 pc[11:0], instr_retired);
                    end
                    return;
                end
            end

            default: ; // anything else decodes to a nop
        endcase

        if (write_rd && (rd != 5'd0)) begin
            regs[rd] = result;
        end

        if (trace) begin
            $display($stime, " Ref: pc 0x%03x  %-44s %s\n", pc[11:0], text,
                     (write_rd && rd != 5'd0) ? $sformatf("x%0d <= 0x%08x", rd, result) : "");
        end

        pc            = next_pc;
        instr_retired = instr_retired + 1;
    endfunction: step

endclass: cpu_ref_model