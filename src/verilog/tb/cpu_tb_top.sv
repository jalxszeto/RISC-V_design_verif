/*
 * Top-level testbench: instantiates the DUT and verification components, runs
 * the directed, external-port, and constrained-random tests, and holds the
 * protocol assertions.
 */
module cpu_tb_top;

    import cpu_tb_pkg::*;

    parameter int DataSize = DATA_W;
    parameter int AddrSize = XBAR_AW;

    string requested_seed = "default";

    int assertion_errors = 0;

    logic clk = 0;
    always #5 clk = ~clk;

    // IF instantiation
    cpu_if #(.DataSize(DataSize), .AddrSize(AddrSize)) cpu_if(.clk(clk));

    // DUT instantiation
    chip_top dut (
        .clk_i(clk),
        .rst_i(cpu_if.cpu.reset),
        .en_cpu_i(cpu_if.cpu.en_cpu),
        .halt_cpu_i(cpu_if.cpu.halt_cpu),
        .cpu_halted_o(cpu_if.cpu.cpu_halted),
        .addr_i(cpu_if.cpu.addr),
        .wdata_i(cpu_if.cpu.wdata),
        .w_en_i(cpu_if.cpu.w_en),
        .r_en_i(cpu_if.cpu.r_en),
        .rdata_o(cpu_if.cpu.rdata),
        .rready_o(cpu_if.cpu.rready)
    );

    // Observation signals from the DUT memory path
    assign cpu_if.cpu_active     = dut.cpu_enable_q;
    assign cpu_if.dsram_en       = dut.dsram_en;
    assign cpu_if.dsram_write_en = dut.dsram_write_en;
    assign cpu_if.dsram_addr     = dut.dsram_addr;
    assign cpu_if.dsram_wdata    = dut.dsram_wdata;
    assign cpu_if.dsram_rdata    = dut.dsram_rdata;

    cpu_tb_pkg::cpu_sequencer #(.DataSize(DataSize), .AddrSize(AddrSize)) seqr;
    cpu_tb_pkg::cpu_driver #(.DataSize(DataSize), .AddrSize(AddrSize))    drv;
    cpu_tb_pkg::cpu_monitor #(.DataSize(DataSize), .AddrSize(AddrSize))   mon;
    cpu_tb_pkg::cpu_sb #(.DataSize(DataSize), .AddrSize(AddrSize))        sb;

    // Record failed assertion
    function void assertion_fail(input string message);
        assertion_errors++;
        $error($stime, " ASSERT: %s\n", message);
    endfunction: assertion_fail

    // Initialize both memories through the DUT's external memory port
    task automatic init_memories();
        $display($stime, " TB: Initializing instruction and data memories\n");
        mon.log_transactions = 1'b0;
        sb.log_transactions = 1'b0;
        for (int i = 0; i < ISRAM_WORDS; i++) begin
            seqr.send_write_trans(word_addr(ISRAM_BASE, i), EBREAK_WORD);
        end
        for (int i = 0; i < DSRAM_WORDS; i++) begin
            seqr.send_write_trans(word_addr(DSRAM_BASE, i), $urandom());
        end
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
        mon.log_transactions = 1'b1;
        sb.log_transactions = 1'b1;
        $display($stime, " TB: Memory initialization complete\n");
    endtask: init_memories

    // Queue external reads on a memory window
    task automatic readback(input int window, input int num_words, input int start_word=0);
        logic [AddrSize-1:0] base;

        case (window)
            0: base = ISRAM_BASE;
            1: base = DSRAM_BASE;
            2: base = REG_BASE;
            default: base = REG_BASE;
        endcase

        for (int i = 0; i < num_words; i++) begin
            seqr.send_read_trans(word_addr(base, start_word + i));
        end
        seqr.wait_for_empty();
        repeat (4) @(cpu_if.cb);
    endtask: readback

    task automatic preload_dmem(input logic [31:0] values [$], input int start_word=0);
        foreach (values[i]) begin
            seqr.send_write_trans(word_addr(DSRAM_BASE, start_word + i), values[i]);
        end
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
    endtask: preload_dmem

    // Run a directed test
    task automatic run_directed(input string name, const ref logic [31:0] program_words [$],
            input int max_cycles=2000, input int dmem_words=16);
        $display("");
        $display("=================================================================");
        $display(" TEST: %s", name);
        $display("=================================================================");
        sb.set_test(name);

        drv.reset_task();
        seqr.load_program(program_words);
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
        drv.run_program(max_cycles);

        if (drv.last_run_completed) begin
            readback(2, REG_COUNT);
            readback(1, dmem_words);
        end else begin
            $display($stime, " TB: Skipping %s readback after CPU timeout\n", name);
            drv.reset_task();
        end
    endtask: run_directed

    // Basic smoke test for loading, running, and observing a program that halts
    task automatic run_smoke_test();
        logic [31:0] smoke_prog [$];
        smoke_prog = '{ EBREAK_WORD };
        run_directed("smoke_ebreak", smoke_prog, 100, 1);
    endtask: run_smoke_test

    // Smoke test for stopping the CPU from outside the program
    // Readback is skipped because the CPU stops before the program completes
    task automatic run_external_halt_smoke();
        logic [31:0] long_prog [$];

        for (int i = 0; i < 32; i++) begin
            long_prog.push_back(asm_instr(.op(OP_ADDI), .rd(1), .rs1(1), .imm(1)));
        end
        long_prog.push_back(EBREAK_WORD);

        $display("");
        $display("=================================================================");
        $display(" TEST: smoke_external_halt");
        $display("=================================================================");
        sb.set_test("smoke_external_halt");

        drv.reset_task();
        seqr.load_program(long_prog);
        seqr.wait_for_empty();
        repeat (2) @(cpu_if.cb);
        drv.start_cpu();
        repeat (12) @(cpu_if.cb);
        drv.halt_cpu_now();
        drv.reset_task();
    endtask: run_external_halt_smoke

    

    // TEST PROGRAM
    logic [31:0] prog [$];
    logic [31:0] data [$];

    int NUM_RANDOM_PROGRAMS = 20;
    int NUM_RANDOM_XBAR = 300;

    initial begin
        int total_errors;

        mon = new(cpu_if);
        sb = new(mon.mon_box);
        seqr = new();
        drv = new(cpu_if, seqr.xbar_box);

        void'($value$plusargs("NUM_RANDOM_PROGRAMS=%d", NUM_RANDOM_PROGRAMS));
        void'($value$plusargs("NUM_RANDOM_XBAR=%d", NUM_RANDOM_XBAR));
        if ($test$plusargs("REF_TRACE")) begin
            sb.ref_model.trace = 1'b1;
        end

        fork
            mon.run();
            sb.run();
            drv.run();
        join_none

        drv.reset_task();
        init_memories();

        run_smoke_test();
        run_external_halt_smoke();


        // DIRECTED TESTS
        drv.reset_task();
        init_memories();

        // Directed tests from the test plan
        
        // addi with a positive immediate
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(1), .imm(100)),
            EBREAK_WORD
        };
        run_directed("addi_positive", prog);

        

        // 1.1
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(-1)),   // x1 = 0 - 1
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1)),    // x2 = 0 + 1
            asm_instr(.op(OP_SRL),  .rd(1), .rs1(1), .rs2(2)),    // x1 = 32'hFFFF_FFFF >> 1
            asm_instr(.op(OP_ADD),  .rd(3), .rs1(1), .rs2(2)),    // x3 = 32'h7FFF_FFFF + 1
            EBREAK_WORD
        };
        run_directed("add_overflow", prog);

        // 1.2
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(-1)),   // x1 = 0 + (-1)
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1)),    // x2 = 0 + 1
            asm_instr(.op(OP_ADD),  .rd(3), .rs1(1), .rs2(2)),    // x3 = -1 + 1
            EBREAK_WORD
        };
        run_directed("add_carry_out", prog);

        // 1.3
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(7)),   // x1 = 0 + 7
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(7)),   // x2 = 0 + 7
            asm_instr(.op(OP_SUB),  .rd(3), .rs1(1), .rs2(2)),   // x3 = 7 - 7
            EBREAK_WORD
        };
        run_directed("sub_zero", prog);

        // 1.4
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(-5)),   // x1 = 0 + (-5)
            EBREAK_WORD
        };
        run_directed("addi_neg_imm", prog);

        // 1.5
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),    // x1 = 1
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(31)),   // x2 = 31
            asm_instr(.op(OP_SLL),  .rd(3), .rs1(1), .rs2(2)),    // x3 = 1 << 31
            EBREAK_WORD
        };
        run_directed("sll_shift31", prog);

        // 1.6
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(-1)),   // x1 = 0 - 1
            asm_instr(.op(OP_SRL),  .rd(2), .rs1(1), .rs2(0)),    // x2 = 32'hFFFF_FFFF >> 0
            EBREAK_WORD
        };
        run_directed("srl_shift0", prog);

        // 1.7
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),    // x1 = 1
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(31)),   // x2 = 31
            asm_instr(.op(OP_SLL),  .rd(3), .rs1(1), .rs2(2)),    // x3 = 1 << 31
            asm_instr(.op(OP_ADD),  .rd(3), .rs1(3), .rs2(1)),    // x3 = 32'h8000_0000 + 1
            asm_instr(.op(OP_SRL),  .rd(3), .rs1(3), .rs2(1)),    // x3 = 32'h8000_0001 >> 1
            EBREAK_WORD
        };
        run_directed("srl_shift1", prog);

        // 1.8
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(0), .rs1(0), .imm(5)),   // attempt: x0 = 0 + 5
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(0)),   // x1 = x0 + 0
            asm_instr(.op(OP_ADD),  .rd(2), .rs1(0), .rs2(0)),   // x2 = x0 + x0
            EBREAK_WORD
        };
        run_directed("read_x0_returns_0", prog);

        // 1.9
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1),  .rs1(0), .imm(103)),   // x1 = 0 + 103
            asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(0)),     // dmem[0] = 103
            asm_instr(.op(OP_LW),   .rd(2),  .rs1(0), .imm(0)),     // x2 = 103
            EBREAK_WORD
        };
        run_directed("sw_lw", prog);

        // 1.10
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),    // addr 0:  x1 = 0 + 5
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(5)),    // addr 4:  x2 = 0 + 5
            asm_instr(.op(OP_BEQ), .rs1(1), .rs2(2), .imm(8)),    // addr 8:  jump to addr 8 + 8
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(6767)), // addr 12: must be skipped
            asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(1)),    // addr 16: x4 = 0 + 1
            EBREAK_WORD
        };
        run_directed("beq_taken_forward", prog);

        // 1.11
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),    // addr 0:  x1 = 0 + 5
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(5)),    // addr 4:  x2 = 0 + 5
            asm_instr(.op(OP_BEQ), .rs1(1), .rs2(2), .imm(8)),    // addr 8:  jump to addr 8 + 8 = 16
            EBREAK_WORD,                                          // addr 12: must be skipped
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(7)),    // addr 16: x3 = 0 + 7
            asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(7)),    // addr 20: x4 = 0 + 7
            asm_instr(.op(OP_BEQ), .rs1(3), .rs2(4), .imm(-12)),  // addr 24: jump to addr 24 - 12 = 12
            asm_instr(.op(OP_ADDI), .rd(5), .rs1(0), .imm(6767)), // addr 28: must be skipped
            EBREAK_WORD                                           // addr 32: safety
        };
        run_directed("beq_taken_backward", prog);

        // 1.12
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),    // addr 0:  x1 = 0 + 5
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(7)),    // addr 4:  x2 = 0 + 7
            asm_instr(.op(OP_BEQ), .rs1(1), .rs2(2), .imm(12)),   // addr 8:  5 != 7, branch not taken
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(1)),    // addr 12: x3 = 0 + 1
            EBREAK_WORD,                                          // addr 16: correct breakpoint
            asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(6767)), // addr 20: must not be executed
            EBREAK_WORD                                           // addr 24: safety
        };
        run_directed("beq_not_taken", prog);

        // 1.13
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),   // x1 = 0 + 5
            asm_instr(.op(OP_ADD),  .rd(2), .rs1(1), .rs2(1)),   // x2 = 5 + 5
            EBREAK_WORD
        };
        run_directed("read_after_write", prog);

        // 1.14
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(103)),  // x1 = 103
            asm_instr(.op(OP_SW),  .rs1(0), .rs2(1), .imm(0)),    // dmem[0] = 103
            asm_instr(.op(OP_LW),   .rd(2), .rs1(0), .imm(0)),    // x2 = 103
            asm_instr(.op(OP_ADD),  .rd(3), .rs1(2), .rs2(2)),    // x3 = 103 + 103
            EBREAK_WORD
        };
        run_directed("lw_use", prog);

        // 1.15
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),    // addr 0:  x1 = 0 + 5
            asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(5)),    // addr 4:  x2 = 0 + 5
            asm_instr(.op(OP_BEQ), .rs1(1), .rs2(2), .imm(8)),    // addr 8:  jump to addr 8 + 8 = 16
            asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(6767)), // addr 12: must be skipped
            EBREAK_WORD                                           // addr 16: correct breakpoint
        };
        run_directed("ebreak_after_branch", prog);


        /*
        // TEST FOR BUG 1: beq compares old value at register if preceded by lw loading new value to register
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(6)),   // x1 = 0 + 6
            asm_instr(.op(OP_SW),  .rs1(0), .rs2(1), .imm(0)),   // dmem[0] = 6
            asm_instr(.op(OP_LW),   .rd(3), .rs1(0), .imm(0)),   // x3 = 6 (0 original value)
            asm_instr(.op(OP_BEQ), .rs1(3), .rs2(0), .imm(8)),   // 6 != 0 (must be skipped)
            asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(1)),   // x4 = 1 (must be executed)
            EBREAK_WORD
        };
        run_directed("bug1", prog);

        

        // TEST FOR BUG 2: an lw preceded by an sw, if the memory address in lw matches the address in sw in at least the lowest 4 bits (excluding lowest 2 for word-alignment), will return value stored by sw, even if entire address for lw does not match that of sw
        prog = '{
            asm_instr(.op(OP_SW),   .rs1(5), .rs2(0),  .imm(344)),  // dmem[86] = 0
            asm_instr(.op(OP_LW),   .rd(4),  .rs1(17), .imm(280)),  // x4 = dmem[54]
            EBREAK_WORD
        };
        run_directed("bug2", prog);
        
        
        
        // TEST FOR BUG 3: beq compares only lowest 8 bits
        prog = '{
            asm_instr(.op(OP_ADDI), .rd(1),  .rs1(0),  .imm(256)),   // x1 = [23 0s]1_0000_0000
            asm_instr(.op(OP_BEQ),  .rs1(0), .rs2(1),  .imm(8)),     // ...0_0000_0000 != ...1_0000_0000 (branch not taken)
            asm_instr(.op(OP_ADDI), .rd(2),  .rs1(0),  .imm(67)),    // x2 = 67 (must be skipped)
            EBREAK_WORD
        };
        run_directed("bug3", prog);

        */



        

        // CONSTRAINED-RANDOM TESTS
        // For every random CPU program:
        //   1. print an iteration label so the seed and failure are reproducible,
        //   2. reset the CPU and call init_memories() before gen_program(),
        //   3. wait for program writes, then run with a bounded timeout,
        //   4. queue the register and memory reads needed by the scoreboard.
        // Randomized external-port traffic runs only while the CPU is stopped.
        // Memory is reinitialized every iteration so the DUT, scoreboard, and
        // generation model start from the same image.


        // Random programs
        for (int i = 0; i < NUM_RANDOM_PROGRAMS; i++) begin
            int len;
            len = $urandom_range(5, 50);

            $display("");
            $display("=================================================================");
            $display(" Random Program Iteration %0d (SVSEED=%0d, length=%0d)", i, $get_initial_random_seed(), len);
            $display("=================================================================");
            sb.set_test($sformatf("random_prog_%0d", i));

            drv.reset_task();
            init_memories();
            seqr.gen_program(len);
            seqr.wait_for_empty();
            repeat (2) @(cpu_if.cb); // Wait for instructions to finish being written
            drv.run_program();

            if (drv.last_run_completed) begin // Program completed cleanly
                readback(1, DSRAM_WORDS);
                readback(2, REG_COUNT);
            end 
            else begin
                $display($stime, " TB: Skipping random_prog_%0d readback after CPU timeout\n", i);
                drv.reset_task();
            end
        end

        // Randomized external-port traffic (CPU stopped)
        $display("");
        $display("=================================================================");
        $display(" Randomized External-Port Traffic (%0d transactions)", NUM_RANDOM_XBAR);
        $display("=================================================================");
        sb.set_test("random_xbar");

        drv.reset_task(); // Stop CPU and ensure memories given to external port
        seqr.gen_xbar(NUM_RANDOM_XBAR);
        seqr.wait_for_empty();
        repeat (4) @(cpu_if.cb); // Ensure last transaction taken by driver




        /*
        // REVERTED ASSERTION VIOLATIONS

        // Violation for 3.1
        force cpu_if.cpu_active = 1'b1;
        drv.xbar_write(word_addr(DSRAM_BASE, 0), 32'h1);
        release cpu_if.cpu_active;



        // Violation for 3.2
        force cpu_if.rready = 1'b0;
        readback(1, 1);
        release cpu_if.rready;
        
        

        // Violation for 3.3
        force cpu_if.rready = 1'b0;
        readback(2, 1);
        release cpu_if.rready;


        // Violation for 3.4
        force cpu_if.cpu_active = 1'b1;
        cpu_if.cb.halt_cpu <= 1'b1;
        @(cpu_if.cb);
        cpu_if.cb.halt_cpu <= 1'b0;
        repeat (4) @(cpu_if.cb);
        release cpu_if.cpu_active;


        // Violation for 3.5
        force cpu_if.cpu_active = 1'b1;
        drv.reset_task();
        release cpu_if.cpu_active;

        */








        // TEST FINISH
        repeat (20) @(cpu_if.cb);
        total_errors = sb.errors + drv.timeouts + mon.errors + assertion_errors;
        if (sb.checks == 0) begin
            $error("Testbench performed zero checks; no results were verified");
        end

        $display("=================================================================");
        $display("  Scoreboard mismatches : %0d", sb.errors);
        $display("  Driver timeouts       : %0d", drv.timeouts);
        $display("  Monitor protocol errs : %0d", mon.errors);
        $display("  Assertion failures    : %0d", assertion_errors);
        $display("=================================================================");
        $display();

        if (total_errors == 0) begin
            $display("=================================================================");
            $display(" TEST PASSED!");
            $display("=================================================================");
        end else begin
            $display("=================================================================");
            $display(" TEST FAILED: %0d error(s)", total_errors);
            $display("=================================================================");
        end
        $finish;
    end

    // Stop a broken DUT or testbench instead of letting the simulation run forever
    initial begin
        #10ms;
        $display(" TEST FAILED - global timeout");
        $fatal(1, "global timeout");
    end

    initial begin
        void'($value$plusargs("SEED_LABEL=%s", requested_seed));
        if ($test$plusargs("BUG_HUNT_WAVES")) begin
            $shm_open("bug_hunt_waves.shm");
        end else begin
            $shm_open("waves.shm");
        end
        $shm_probe("AC");
    end

    wire rst = cpu_if.reset;
    // Protocol and control assertions (see testplan.md section 3)

    NO_SIMULTANEOUS_READ_WRITE:
        assert property (@(posedge clk) disable iff (rst)
            !(cpu_if.w_en && cpu_if.r_en))
        else assertion_fail("w_en_i and r_en_i were asserted together");
    

    EXTERNAL_PORT_ONLY_WHEN_DISABLED:
        assert property (@(posedge clk) disable iff (rst)
            !(cpu_if.cpu_active && (cpu_if.w_en || cpu_if.r_en)))
        else assertion_fail("External port request (w_en/r_en) issued while CPU is active");

    SRAM_WINDOW_RESPONDS_NEXT_CYCLE:
        assert property (@(posedge clk) disable iff (rst)
            (cpu_if.r_en && (cpu_if.addr[13:12] inside {2'b00, 2'b01})) |-> ##1 cpu_if.rready)
        else assertion_fail("SRAM window read did not respond on following cycle");

    REG_WINDOW_RESPONDS_SAME_CYCLE:
        assert property (@(posedge clk) disable iff (rst)
            (cpu_if.r_en && cpu_if.addr[13:12] == 2'b10) |-> cpu_if.rready)
        else assertion_fail("Register-file window read did not respond in the same cycle");

    CPU_RELEASES_AFTER_HALT:
        assert property (@(posedge clk) disable iff (rst)
            (cpu_if.halt_cpu || cpu_if.cpu_halted) |-> ##2 !cpu_if.cpu_active)
        else assertion_fail("CPU did not release memories two cycles after halt");

    RESET_RELEASES_CPU:
        assert property (@(posedge clk)
            rst |-> ##1 !cpu_if.cpu_active)
        else assertion_fail("CPU still active after reset");


endmodule: cpu_tb_top
