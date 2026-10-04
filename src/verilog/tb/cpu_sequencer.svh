/*
 * Builds programs and external-port transactions, then sends them to the
 * driver through xbar_box. The sequencer describes intent but never drives or
 * observes the DUT directly.
 */
class cpu_sequencer #(int DataSize=32, int AddrSize=14);

    mailbox #(cpu_xbar_item #(DataSize, AddrSize)) xbar_box;

    // Mirror data-memory initialization writes. gen_program starts a private
    // reference model from this image and advances it only along the generated
    // program's reachable path. This is generation context, not DUT checking.
    logic [31:0] shadow_dmem [DSRAM_WORDS];

    // Constructor
    function new();
        xbar_box = new();
        foreach (shadow_dmem[i]) begin
            shadow_dmem[i] = '0;
        end
    endfunction: new

    // Build a random program and enqueue frontdoor instruction writes.
    // idx and prog_len are assigned before randomization because branch
    // constraints depend on the instruction's position.
    task gen_program(input int num, input bit verbose=1'b1);
        cpu_seq_item #(DataSize, AddrSize) instr;
        cpu_ref_model shadow;
        logic [31:0] program_words [$];
        logic [31:0] effective_addr;
        bit reachable;
        int prog_len;

        if ((num < 0) || (num >= ISRAM_WORDS)) begin
            $fatal(1,
                    "%0t Seq: program needs 0..%0d random instructions, got %0d",
                    $time, ISRAM_WORDS - 1, num);
        end

        prog_len = num + 1; // +1 for the ebreak
        shadow = new();
        shadow.load_dmem(shadow_dmem);

        for (int i = 0; i < num; i++) begin
            instr = new();
            instr.idx = i;
            instr.prog_len = prog_len;
            foreach (shadow.regs[r]) begin
                instr.reg_snapshot[r] = shadow.regs[r];
            end
            if (!instr.randomize()) begin
                $fatal(1, "%0t Seq: state-aware randomization failed for instruction %0d",
                        $time, i);
            end

            // Independent check on c_mem_align. If it fires, the generated
            // instruction violated the effective-address rule on that constraint.
            if (instr.op inside {OP_LW, OP_SW}) begin
                effective_addr = instr.reg_snapshot[instr.rs1] + instr.imm;
                if ((effective_addr[1:0] != 2'b00) ||
                        (effective_addr > ((DSRAM_WORDS * 4) - 4))) begin
                    $fatal(1,
                            "%0t Seq: illegal effective byte address 0x%08x for %s; check c_mem_align",
                            $time, effective_addr, instr.asm());
                end
            end
            if (verbose) begin
                instr.display();
            end
            program_words.push_back(instr.encode());

            // Taken forward branches may skip generated slots. They still
            // belong in instruction memory, but skipped instructions must not
            // change the state seen by a later reachable instruction.
            reachable = !shadow.halted && (shadow.pc[11:2] == i);
            shadow.imem[i] = instr.encode();
            if (reachable) begin
                shadow.step();
            end
        end

        // Append ebreak explicitly so a random program cannot halt early
        instr = new();
        instr.idx = num;
        instr.prog_len = prog_len;
        instr.op = OP_EBREAK;
        instr.rs1 = '0;
        instr.rs2 = '0;
        instr.rd = '0;
        instr.imm = 0;
        if (verbose) begin
            instr.display();
        end
        program_words.push_back(instr.encode());
        shadow.imem[num] = instr.encode();

        if (!shadow.halted && (shadow.pc[11:2] == num)) begin
            shadow.step();
        end
        if (!shadow.halted) begin
            $fatal(1,
                    "%0t Seq: generated control flow missed the final ebreak (pc=0x%08x); complete c_branch_target",
                    $time, shadow.pc);
        end

        foreach (program_words[i]) begin
            send_write_trans(word_addr(ISRAM_BASE, i), program_words[i]);
        end
    endtask: gen_program

    // Stage one external write transaction
    task send_write_trans(input logic [AddrSize-1:0] addr, input logic [DataSize-1:0] data);
        cpu_xbar_item #(DataSize, AddrSize) trans;

        trans = new();
        trans.kind = XBAR_WRITE;
        trans.addr = addr;
        trans.data = data;
        trans.is_write = 1'b1;
        if ((window_of(addr) == WIN_DSRAM) && (addr[1:0] == 2'b00)) begin
            shadow_dmem[addr[11:2]] = data;
        end
        xbar_box.put(trans);
    endtask: send_write_trans

    // Stage one external read transaction
    task send_read_trans(input logic [AddrSize-1:0] addr);
        cpu_xbar_item #(DataSize, AddrSize) trans;

        trans = new();
        trans.kind = XBAR_READ;
        trans.addr = addr;
        trans.is_write = 1'b0;
        xbar_box.put(trans);
    endtask: send_read_trans

    // Stage a program as instruction-memory writes starting at word zero
    task load_program(const ref logic [31:0] prog [$]);
        foreach (prog[i]) begin
            send_write_trans(word_addr(ISRAM_BASE, i), prog[i]);
        end
    endtask: load_program

    // Generate external-port traffic. cpu_xbar_item constraints define the
    // useful behavior.
    task gen_xbar(input int num, input bit verbose=1'b0);
        cpu_xbar_item #(DataSize, AddrSize) trans;

        for (int i = 0; i < num; i++) begin
            trans = new();
            if (!trans.randomize()) begin
                $error($stime, " Seq: randomization failed for xbar item %0d\n", i);
            end
            if (verbose) begin
                trans.display();
            end
            xbar_box.put(trans);
        end
    endtask: gen_xbar

    // Wait until the driver has pulled every staged mailbox transaction
    task wait_for_empty();
        while (xbar_box.num() != 0) begin
            #10;
        end
    endtask: wait_for_empty

endclass: cpu_sequencer
