/*
 * Testbench view of the chip interface. It contains chip_top ports and
 * observation taps in the wrapper/memory logic, but no signals from the CPU
 * microarchitecture. The clocking block defines when the
 * driver writes signals and when the monitor samples them.
 */
interface cpu_if #(int DataSize = 32, int AddrSize = 14) (input wire clk);

  // Chip-level control (chip_top ports)

  // Active-high reset
  logic reset = 1;

  // Pulsed high to release the CPU and let it start executing
  logic en_cpu = 1'b0;

  // Pulsed high to freeze the CPU part way through a program
  logic halt_cpu = 1'b0;

  // Asserted by the CPU when it retires an ebreak
  logic cpu_halted;

  /*
   * External "crossbar" port (chip_top ports). This is the only external path
   * to memory and architectural state, and it is serviced only while the CPU
   * is disabled:
   *   addr[13:12] == 2'b00 -> instruction SRAM
   *   addr[13:12] == 2'b01 -> data SRAM
   *   addr[13:12] == 2'b10 -> register file (read only)
   */
  logic [AddrSize-1:0] addr = '0;
  logic [DataSize-1:0] wdata = '0;
  logic                w_en = 1'b0;
  logic                r_en = 1'b0;
  logic [DataSize-1:0] rdata;
  logic                rready;

  /*
   * Observation taps driven from chip_top. They expose CPU data-memory
   * activity without depending on the CPU's internal microarchitecture.
   */

  // chip_top.cpu_enable_q - high while the CPU owns the memories
  logic                cpu_active;

  // memory_controller -> data SRAM port
  logic                dsram_en;
  logic                dsram_write_en;
  logic [9:0]          dsram_addr;
  logic [DataSize-1:0] dsram_wdata;
  logic [DataSize-1:0] dsram_rdata;

  /*
   * Clocking block sampling inputs one precision step before the rising edge
   * and driving outputs two time units afterward to avoid RTL races.
   */
  clocking cb @(posedge clk);
    default input #1step output #2;
    input  cpu_halted, rdata, rready, cpu_active,
           dsram_en, dsram_write_en, dsram_addr, dsram_wdata, dsram_rdata;
    // Declared inout so the monitor can sample 
    inout  reset, en_cpu, halt_cpu,
           addr, wdata, w_en, r_en;
  endclocking

  // Signals connected to the DUT from the DUT's point of view
  modport cpu(
    input  reset, en_cpu, halt_cpu, addr, wdata, w_en, r_en,
    output cpu_halted, rdata, rready
  );

endinterface
