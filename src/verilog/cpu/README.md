# RISC-V CPU

SystemVerilog RTL for the CPU under test. It implements `add`, `addi`, `sub`, `sll`, `srl`, `lw`,
`sw`, `beq`, and `ebreak`.

| File | Purpose |
| --- | --- |
| `cpu_pkg.sv` | Shared definitions, including the instruction-type enum |
| `cpu_top.sv` | Core top level: connects the stages, handles load stalls, data SRAM access, and halt |
| `fetch.sv` | Program counter and instruction fetch from instruction SRAM |
| `decode.sv` | Instruction decode and immediate generation |
| `execute.sv` | ALU, memory address calculation, and branch resolution |
| `reg_file.sv` | 32 x 32-bit register file with `x0` hardwired to zero |

The source list is `sim/behav/Include/cpu.include`. The encrypted CPU variants used for the bug
hunt are in `src/verilog/bug_hunt_cpu_*/` and are selected by `make bug_hunt`.
