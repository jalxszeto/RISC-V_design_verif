/*
 * Converts sequences from the sequencer into signals that drive the external
 * port of the DUT. This is the only class that drives the DUT. It uses the
 * clocking block to avoid races with the monitor.
 *
 * Check memory_controller to see how it arbitrates memory ownership between
 * the CPU and the external port, and acts as a crossbar (xbar) to route external
 * access to ISRAM, DSRAM, and registers.
 */
class cpu_driver #(int DataSize=32, int AddrSize=14);

    virtual interface cpu_if #(.DataSize(DataSize), .AddrSize(AddrSize)) cpuVif;

    mailbox #(cpu_xbar_item #(DataSize, AddrSize)) xbar_box;

    // Maximum cycles to wait for an external read to finish
    int xbar_timeout = 32;

    // Maximum cycles to wait for the CPU to halt
    int run_timeout = 20000;

    int timeouts;                // Counts timeout failures
    bit last_run_completed;      // High when the CPU reports a clean halt

    // Constructor
    function new(virtual interface cpu_if #(DataSize, AddrSize) cpuVif,
                 mailbox #(cpu_xbar_item #(DataSize, AddrSize)) xbar_box);
      this.cpuVif   = cpuVif;
      this.xbar_box = xbar_box;
      this.timeouts = 0;
      this.last_run_completed = 1'b0;
    endfunction: new

    // Put the DUT into a known reset state
    task reset_task();
        // Drive all requests inactive, hold reset for several clock cycles,
        // then release it and give the interface time to settle

        // Drive all requests inactive
        cpuVif.cb.en_cpu <= 1'b0;
        cpuVif.cb.halt_cpu <= 1'b0;
        cpuVif.cb.w_en <= 1'b0;
        cpuVif.cb.r_en <= 1'b0;
        cpuVif.cb.addr <= 14'b0;
        cpuVif.cb.wdata <= 32'b0;

        // Hold reset for several clock cycles
        cpuVif.cb.reset <= 1'b1;
        repeat (4) @(cpuVif.cb);
        cpuVif.cb.reset <= 1'b0;

        // Give the interface time to settle
        repeat (5) @(cpuVif.cb);

    endtask: reset_task

    // Send one write through the DUT's external memory port
    task xbar_write(input logic [AddrSize-1:0] addr, input logic [DataSize-1:0] data);
        if (addr[1:0] != 2'b00) begin
            $error($stime, " Drv: external write address 0x%0x is not word aligned\n", addr);
        end

        // Drive one external write through the clocking block for one cycle,
        // then return the port to idle

        // Wait until posedge
        @(cpuVif.cb);

        // Drive external write
        cpuVif.cb.addr <= addr;
        cpuVif.cb.wdata <= data;
        cpuVif.cb.w_en <= 1'b1;
        @(cpuVif.cb);

        // Return port to idle
        cpuVif.cb.w_en <= 1'b0;



    endtask: xbar_write

    // Send one read through the external memory port and wait for its data
    task xbar_read(input logic [AddrSize-1:0] addr);
        bit timed_out;
        int count;

        // Readback data
        logic [DataSize-1:0] data;

        if (addr[1:0] != 2'b00) begin
            $error($stime, " Drv: external read address 0x%0x is not word aligned\n", addr);
        end

        // Hold the request stable until rready, capture the returned data,
        // and time out if no response arrives

        timed_out = 1'b0;
        count = 0;

        // Wait until posedge
        @(cpuVif.cb);

        // Drive external read
        cpuVif.cb.addr <= addr;
        cpuVif.cb.r_en <= 1'b1;
        
        // Wait until rready or timeout
        forever begin
            @(cpuVif.cb);
            count++;
            if (cpuVif.cb.rready) begin
                data = cpuVif.cb.rdata;
                break;
            end
            if (count >= xbar_timeout) begin 
                timed_out = 1'b1;
                timeouts++;
                $error($stime, " Drv: external read at address 0x%0x timed out after %0d cycles\n", addr, count);
                break;
            end
        end

        // Return port to idle
        cpuVif.cb.r_en <= 1'b0;

    endtask: xbar_read

    // Drive a start request for one CPU run
    task start_cpu();
        // Pulse en_cpu for one cycle

        @(cpuVif.cb);
        cpuVif.cb.en_cpu <= 1'b1;

        @(cpuVif.cb);
        cpuVif.cb.en_cpu <= 1'b0;

    
    endtask: start_cpu

    // Wait for the CPU to halt, or fail after the allowed number of cycles
    task wait_for_halt(output int cycles, input int max_cycles=0);
        int limit;

        limit  = (max_cycles == 0) ? run_timeout : max_cycles;
        cycles = 0;

        // Check cpu_halted every cycle and report how many cycles ran.
        // last_run_completed is set only after a real halt. On a timeout,
        // timeouts is incremented and the flag stays low so the testbench can recover.


        last_run_completed = 1'b0;

        forever begin 
            @(cpuVif.cb);
            cycles++;
            
            // Halt
            if (cpuVif.cb.cpu_halted) begin 
                last_run_completed = 1'b1;
                $display($stime, " Drv: CPU halted after %0d cycles\n", cycles);
                break;
            end

            // Timeout
            if (cycles >= limit) begin
                timeouts++;
                $error($stime, " Drv: CPU did not halt within %0d cycles\n", limit);
                break;
            end
        end

    endtask: wait_for_halt

    // Start CPU and wait for it to halt
    task run_program(input int max_cycles=0);
        int cycles;

        last_run_completed = 1'b0;
        start_cpu();
        wait_for_halt(cycles, max_cycles);
    endtask: run_program

    // Stop a program through an external halt and wait for memory ownership
    // to return to the external port
    task halt_cpu_now();
        // Assert an external halt request and wait, with a bound, until
        // ownership returns to the external port

        int count = 0; // Number of cycles until ownership returns to external port

        @(cpuVif.cb);
        cpuVif.cb.halt_cpu <= 1'b1;

        forever begin 
            @(cpuVif.cb);
            count++;

            // Memories restored to external port
            if (!cpuVif.cb.cpu_active) begin 
                break;
            end

            // Timeout
            if (count >= xbar_timeout) begin 
                timeouts++;
                $error($stime, " Drv: CPU did not release memories within %0d cycles of external halt\n", count);
                break;
            end
        end

        cpuVif.cb.halt_cpu <= 1'b0;

    endtask: halt_cpu_now

    // Main driver loop. Keeps taking transactions from the mailbox and
    // driving them through the DUT
    task run();
        cpu_xbar_item #(DataSize, AddrSize) trans;

        forever begin
            xbar_box.get(trans);
            if (trans.is_write) begin
                xbar_write(trans.addr, trans.data);
            end else begin
                xbar_read(trans.addr);
            end
        end
    endtask: run

endclass: cpu_driver