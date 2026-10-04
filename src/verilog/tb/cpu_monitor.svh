/*
 * Watches the DUT interface and sends observed events to the scoreboard. It
 * keeps enough state to match requests with responses, including responses
 * that take more than one cycle.
 */
class cpu_monitor #(int DataSize=32, int AddrSize=14);

    virtual interface cpu_if #(.DataSize(DataSize), .AddrSize(AddrSize)) cpuVif;

    mailbox #(cpu_xbar_item #(DataSize, AddrSize)) mon_box;

    // State for external reads
    bit                  pending_read;                 // A read is waiting for rready
    logic [AddrSize-1:0] pending_read_addr;            // Address of that read

    // State for CPU data-memory requests
    bit                  load_in_flight;    // A CPU load is waiting for data
    logic [9:0]          load_addr;         // Address of that load
    bit                  prev_store_valid;  // A store was still active last cycle
    logic [9:0]          prev_store_addr;   // Address of that store
    logic [DataSize-1:0] prev_store_data;   // Data for that store
    bit                  prev_load_valid;   // A load was still active last cycle
    logic [9:0]          prev_load_addr;    // Address of that load

    // Detecting state changes
    bit prev_cpu_active;          // Previous CPU memory-ownership state
    bit prev_cpu_halted;          // Previous CPU halt state
    bit prev_reset;               // Previous reset state
    int errors;                   // Number of interface errors found

    bit log_transactions;         // Optional transaction logging flag

    // Constructor
    function new(virtual interface cpu_if #(DataSize, AddrSize) cpuVif);
        this.cpuVif = cpuVif;
        this.mon_box = new();
        this.pending_read     = 1'b0;
        this.load_in_flight   = 1'b0;
        this.prev_store_valid = 1'b0;
        this.prev_load_valid  = 1'b0;
        this.prev_cpu_active  = 1'b0;
        this.prev_cpu_halted  = 1'b0;
        this.prev_reset       = 1'b0;
        this.log_transactions = 1'b1;
        this.errors           = 0;
    endfunction: new

    // Create a transaction for an observed event and send it to the scoreboard
    task send(input trans_kind_e kind,
              input logic [AddrSize-1:0] addr, input logic [DataSize-1:0] data,
              input logic is_write=1'b0);

        // Create an xbar transaction and send it to the scoreboard

        cpu_xbar_item #(DataSize, AddrSize) item;
        item = new();
        item.kind = kind;
        item.addr = addr;
        item.data = data;
        item.is_write = is_write;

        mon_box.put(item);

    endtask: send

    // Match each external read request with its response
    task observe_external_read();
        // Save the address when a request starts and send one XBAR_READ when
        // rready shows rdata is valid. Register-file reads respond in the
        // request cycle; SRAM reads respond on the following cycle.

        // New request (first cycle)
        if (!pending_read) begin 
            // Register
            if (cpuVif.cb.rready) begin 
                send(XBAR_READ, cpuVif.cb.addr, cpuVif.cb.rdata);
            end
            // SRAM
            else begin 
                pending_read = 1'b1;
                pending_read_addr = cpuVif.cb.addr;
            end
        end
        // Read is waiting
        else begin 
            if (cpuVif.cb.rready) begin 
                send(XBAR_READ, pending_read_addr, cpuVif.cb.rdata);
                pending_read = 1'b0;
            end
        end

    endtask: observe_external_read

    // Report each CPU data-memory request once
    task observe_cpu_memory();
        // Report each CPU data-memory request once: a CPU_LOAD when its read
        // data returns and a CPU_STORE when its write completes, even if the
        // request stays active during an SRAM wait. Saved state is cleared
        // after the request ends.

        bit is_store = cpuVif.cb.cpu_active && cpuVif.cb.dsram_en && cpuVif.cb.dsram_write_en;
        bit is_load = cpuVif.cb.cpu_active && cpuVif.cb.dsram_en && !cpuVif.cb.dsram_write_en;

        // Load waiting for data
        if (load_in_flight) begin 
           send(CPU_LOAD, word_addr(DSRAM_BASE, load_addr), cpuVif.cb.dsram_rdata, 1'b0); 
           load_in_flight = 0;
        end
        // New load
        if (is_load && !(prev_load_valid && cpuVif.cb.dsram_addr == prev_load_addr)) begin 
            load_in_flight = 1;
            load_addr = cpuVif.cb.dsram_addr;
        end
        // New store
        if (is_store && !(prev_store_valid && cpuVif.cb.dsram_addr == prev_store_addr && cpuVif.cb.dsram_wdata == prev_store_data)) begin 
            send(CPU_STORE, word_addr(DSRAM_BASE, cpuVif.cb.dsram_addr), cpuVif.cb.dsram_wdata, 1'b1);
        end

        prev_load_valid = is_load;
        prev_load_addr = cpuVif.cb.dsram_addr;

        prev_store_valid = is_store;
        prev_store_addr = cpuVif.cb.dsram_addr;
        prev_store_data = cpuVif.cb.dsram_wdata;

    endtask: observe_cpu_memory

    // Monitor the DUT once per clock and pass new events to the scoreboard
    task run();
        forever begin
            @(cpuVif.cb);

            if (cpuVif.cb.reset && !prev_reset) begin
                send(DUT_RESET, '0, '0);
                pending_read = 1'b0;
                load_in_flight = 1'b0;
                prev_store_valid = 1'b0;
                prev_load_valid = 1'b0;
                $display($stime, " Mon: Reset asserted\n");
            end
            prev_reset = cpuVif.cb.reset;

            if (cpuVif.cb.cpu_active && !prev_cpu_active) begin
                send(CPU_START, '0, '0);
                $display($stime, " Mon: CPU started executing\n");
            end

            if (cpuVif.cb.cpu_halted && !prev_cpu_halted) begin
                send(CPU_HALT, '0, '0);
                $display($stime, " Mon: cpu_halted_o asserted\n");
            end

            if (cpuVif.cb.w_en && !cpuVif.cb.cpu_active) begin
                if (log_transactions) begin
                    $display($stime, " Mon: External write Addr: 0x%04x, Data: 0x%08x\n",
                             cpuVif.cb.addr, cpuVif.cb.wdata);
                end
                
                send(XBAR_WRITE, cpuVif.cb.addr, cpuVif.cb.wdata, 1'b1);
            end

            if ((cpuVif.cb.r_en && !cpuVif.cb.cpu_active) || pending_read) begin
                observe_external_read();
            end

            if (load_in_flight || (cpuVif.cb.cpu_active && cpuVif.cb.dsram_en) ||
                prev_store_valid || prev_load_valid) begin
                observe_cpu_memory();
            end

            prev_cpu_active = cpuVif.cb.cpu_active;
            prev_cpu_halted = cpuVif.cb.cpu_halted;
        end
    endtask: run

endclass: cpu_monitor