/*
 * Shared testbench package: memory-map constants, transaction/reference
 * types, instruction helpers, and class includes. It deliberately does not
 * import cpu_pkg, keeping the testbench independent of the CPU's internal
 * implementation.
 */
package cpu_tb_pkg;

    // Chip parameters and memory map. The byte-addressed external port uses
    // addr[13:12] to select 4 KiB windows
    parameter int DATA_W      = 32;
    parameter int XBAR_AW     = 14;
    parameter int ISRAM_WORDS = 1024;
    parameter int DSRAM_WORDS = 1024;
    parameter int REG_COUNT   = 32;

    parameter logic [XBAR_AW-1:0] ISRAM_BASE = 14'h0000; // instruction SRAM
    parameter logic [XBAR_AW-1:0] DSRAM_BASE = 14'h1000; // data SRAM
    parameter logic [XBAR_AW-1:0] REG_BASE   = 14'h2000; // register file, read only

    // ebreak encoding used to terminate test programs
    parameter logic [31:0] EBREAK_WORD = 32'h0010_0073;

    // Reference-model bound for detecting nonterminating programs
    parameter int MAX_REF_INSTR = 100000;

    // Transaction and reference-model types

    // Supported instructions. OP_NOP represents unsupported encodings, which
    // both the DUT specification and reference model treat as no-ops
    typedef enum {
        OP_NOP,
        OP_ADD,
        OP_ADDI,
        OP_SUB,
        OP_SLL,
        OP_SRL,
        OP_LW,
        OP_SW,
        OP_BEQ,
        OP_EBREAK
    } instr_e;

    // External-port windows; WIN_NONE represents addr[13:12] == 2'b11
    typedef enum {
        WIN_ISRAM,
        WIN_DSRAM,
        WIN_REG,
        WIN_NONE
    } xbar_win_e;

    // What the monitor observed
    typedef enum {
        XBAR_WRITE,   // the testbench wrote through the external port
        XBAR_READ,    // the testbench read through the external port
        CPU_LOAD,     // the CPU read data memory
        CPU_STORE,    // the CPU wrote data memory
        CPU_START,    // the CPU was released
        CPU_HALT,     // cpu_halted_o went high
        DUT_RESET     // reset was asserted
    } trans_kind_e;

    // One store the reference model expects the CPU to perform
    typedef struct {
        logic [9:0]  addr;
        logic [31:0] data;
    } ref_store_t;

    // Shared address, decode, immediate, and assembly helpers

    // Convert a word index into a byte-addressed, word-aligned port address
    function automatic logic [XBAR_AW-1:0] word_addr(
            input logic [XBAR_AW-1:0] base, input int index);
        return base + (index << 2);
    endfunction: word_addr

    // Which window an external address falls in
    function automatic xbar_win_e window_of(input logic [XBAR_AW-1:0] addr);
        case (addr[13:12])
            2'b00: return WIN_ISRAM;
            2'b01: return WIN_DSRAM;
            2'b10: return WIN_REG;
            default: return WIN_NONE;
        endcase
    endfunction: window_of

    // Testbench components
    `include "cpu_seq_item.svh"
    `include "cpu_xbar_item.svh"
    `include "cpu_ref_model.svh"
    `include "cpu_sequencer.svh"
    `include "cpu_driver.svh"
    `include "cpu_monitor.svh"
    `include "cpu_sb.svh"

    // Build one instruction word through cpu_seq_item so directed
    // and random tests share one encoder. Named arguments read like assembly:
    //   asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(-5))
    function automatic logic [31:0] asm_instr(input instr_e op, input int rd=0,
            input int rs1=0, input int rs2=0, input int imm=0);
        cpu_seq_item #(DATA_W, XBAR_AW) item;

        item = new();
        item.op = op;
        item.rd = rd[4:0];
        item.rs1 = rs1[4:0];
        item.rs2 = rs2[4:0];
        item.imm = imm;
        return item.encode();
    endfunction: asm_instr

endpackage: cpu_tb_pkg