# RISC-V CPU Verification Test Plan

## Document information

| Field | Value |
| --- | --- |
| Verification engineer | Jonathan Szeto |
| Plan revision | Final |
| Date | 2026-10-01 |

### Revision history

| Revision | Date | Changes |
| --- | --- | --- |
| Initial | 2026-09-25 | Initial planned tests |
| Final | 2026-10-01 | Added assertions 3.3–3.5, completed partial and open constraints, added bug hunt results  |

## 1. Functional tests

### Functional-test summary

| Test ID | Test name | Functionality being tested | Expected result | Status |
| --- | --- | --- | --- | --- |
| 1.1 | `add_overflow` | Integer overflow during addition | `add` correctly performs 32-bit addition when sum exceeds signed max/min value: `(x1 + x2) mod 2^32` (unsigned addition) | Passed |
| 1.2 | `add_carry_out` | Addition discards carry-out bit correctly | `add` wraps around to zero when sum exceeds 32-bit range | Passed |
| 1.3 | `sub_zero` | No residual nonzero values during subtraction | `sub` produces zero when operands are equal: `32'h00000000` | Passed |
| 1.4 | `addi_neg_imm` | Sign extension of `imm` in immediate addition | `addi` sign-extends a negative 12-bit `imm` to 32 bits before addition rather than zero-extending it | Passed |
| 1.5 | `sll_shift31` | Zero padding during left shifting | `sll` by max number of bits (31 or `11111`) moves bit 0 to bit 31 and fills rest of bits with 0s| Passed |
| 1.6 | `srl_shift0` | Operand shifts only when instructed to | `srl` does not change number when shifting by 0 | Passed |
| 1.7 | `srl_shift1` | Zero extension during right shifting | `srl` shifts all bits over by 1 to the right and fills top bit with 0 | Passed |
| 1.8 | `read_x0_returns_0` | `x0` is immutable | After attempts to corrupt `x0` using `addi` readback of `x0` is consistent with its value remaining 0 | Passed |
| 1.9 | `sw_lw` | Data round trips through real data memory | Value written by `sw` is correctly read back by later `lw` from the same address | Passed |
| 1.10 | `beq_taken_forward` | Correct instruction execution after branch is taken | With operands equal, `beq` redirects fetch to `current_pc + imm` and skips set instructions in between | Passed |
| 1.11 | `beq_taken_backward` | Sign extension of `imm` in branch instruction | `beq` sign-extends negative `imm` and redirects fetch to earlier target address instead of interpreting `imm` as large positive number | Passed |
| 1.12 | `beq_not_taken` | Sequential instruction execution after branch is not taken | With operands unequal, `beq` does not redirect fetch and execution proceeds to next instruction | Passed |
| 1.13 | `read_after_write` | Instruction reading is correctly ordered across clock edge | Instruction that reads register after previous instruction wrote it uses newly written value | Passed |
| 1.14 | `lw_use` | Stall-release timing for `lw` functions correctly | `lw` takes correct value from memory (after tick finishes) | Passed |
| 1.15 | `ebreak_after_branch` | CPU halts branch and directs fetch to breakpoint | `beq` with operands equal and target address containing `ebreak` halts execution | Passed |

### Functional-test details

### 1.1 — `add_overflow`

**Functionality:**  Integer overflow during addition

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(-1)),   // x1 = 0 - 1
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1)),    // x2 = 0 + 1
  asm_instr(.op(OP_SRL),  .rd(1), .rs1(1), .rs2(2)),    // x1 = 32'hFFFF_FFFF >> 1
  asm_instr(.op(OP_ADD),  .rd(3), .rs1(1), .rs2(2)),    // x3 = 32'h7FFF_FFFF + 1
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h7FFF_FFFF` | `32'hFFFF_FFFF >> 1` |
| `x2` | `32'h0000_0001` | `x0 (0) + 1` |
| `x3` | `32'h8000_0000` | `x1 + x2` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2`, `x3` differs from its reset value; data memory unchanged

**Final result:** Pass: `85675 SB: External read register x3, Expected 0x80000000, Matches Actual 0x80000000`

### 1.2 — `add_carry_out`

**Functionality:**  Addition discards carry-out bit correctly

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(-1)),   // x1 = 0 + (-1)
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(1)),    // x2 = 0 + 1
  asm_instr(.op(OP_ADD),  .rd(3), .rs1(1), .rs2(2)),    // x3 = -1 + 1
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'hFFFF_FFFF` | `x0 (0) - 1` |
| `x2` | `32'h0000_0001` | `x0 (0) + 1` |
| `x3` | `32'h0000_0000` | `x1 + x2` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2`, `x3` differs from its reset value; data memory unchanged

**Final result:** Pass: `87065 SB: External read register x3, Expected 0x00000000, Matches Actual 0x00000000`

### 1.3 — `sub_zero`

**Functionality:**  No residual nonzero values during subtraction

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(7)),   // x1 = 0 + 7
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(7)),   // x2 = 0 + 7
  asm_instr(.op(OP_SUB),  .rd(3), .rs1(1), .rs2(2)),   // x3 = 7 - 7
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h0000_0007` | `x0 (0) + 7` |
| `x2` | `32'h0000_0007` | `x0 (0) + 7` |
| `x3` | `32'h0000_0000` | `x1 - x2` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2`, `x3` differs from its reset value; data memory unchanged

**Final result:** Pass: `88455 SB: External read register x3, Expected 0x00000000, Matches Actual 0x00000000`

### 1.4 — `addi_neg_imm`

**Functionality:**  Sign extension of `imm` in immediate addition

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(-5)),   // x1 = 0 + (-5)
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'hFFFF_FFFB` | `0 + (-5)` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; value of `x1` is as above; no register other than `x1`  differs from its reset value; data memory unchanged

**Final result:** Pass: `89745 SB: External read register x1, Expected 0xfffffffb, Matches Actual 0xfffffffb`

### 1.5 — `sll_shift31`

**Functionality:**  Zero padding during left shifting

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),    // x1 = 1
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(31)),   // x2 = 31
  asm_instr(.op(OP_SLL),  .rd(3), .rs1(1), .rs2(2)),    // x3 = 1 << 31
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h0000_0001` | `x0 (0) + 1` |
| `x2` | `32'h0000_001F` | `x0 (0) + 31` |
| `x3` | `32'h8000_0000` | `x1 << x2` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2`, `x3` differs from its reset value; data memory unchanged

**Final result:** Pass: `91175 SB: External read register x3, Expected 0x80000000, Matches Actual 0x80000000`

### 1.6 — `srl_shift0`

**Functionality:**  Operand shifts only when instructed to

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(-1)),   // x1 = 0 - 1
  asm_instr(.op(OP_SRL),  .rd(2), .rs1(1), .rs2(0)),    // x2 = 32'hFFFF_FFFF >> 0
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'hFFFF_FFFF` | `x0 (0) - 1` |
| `x2` | `32'hFFFF_FFFF` | `x1 >> x0 (0)` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2` differs from its reset value; data memory unchanged

**Final result:** Pass: `92515 SB: External read register x2, Expected 0xffffffff, Matches Actual 0xffffffff`

### 1.7 — `srl_shift1`

**Functionality:**  Zero extention during right shifting

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(1)),    // x1 = 1
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(31)),   // x2 = 31
  asm_instr(.op(OP_SLL),  .rd(3), .rs1(1), .rs2(2)),    // x3 = 1 << 31
  asm_instr(.op(OP_ADD),  .rd(3), .rs1(3), .rs2(1)),    // x3 = 32'h8000_0000 + 1
  asm_instr(.op(OP_SRL),  .rd(3), .rs1(3), .rs2(1)),    // x3 = 32'h8000_0001 >> 1
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h0000_0001` | `x0 (0) + 1` |
| `x2` | `32'h0000_001F` | `x0 (0) + 31` |
| `x3` | `32'h4000_0000` | `x3 (32'h8000_0001) >> x1` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2`, `x3` differs from its reset value; data memory unchanged

**Final result:** Pass: `93985 SB: External read register x3, Expected 0x40000000, Matches Actual 0x40000000`

### 1.8 — `read_x0_returns_0`

**Functionality:**  `x0` is immutable

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(0), .rs1(0), .imm(5)),   // attempt: x0 = 0 + 5
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(0)),   // x1 = x0 + 0
  asm_instr(.op(OP_ADD),  .rd(2), .rs1(0), .rs2(0)),   // x2 = x0 + x0
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x0` | `32'h0000_0000` | `x0` is immutable |
| `x1` | `32'h0000_0000` | `x0 (0) + 0` |
| `x2` | `32'h0000_0000` | `x0 (0) + x0 (0)` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2` differs from its reset value; data memory unchanged

**Final result:** Pass: `95315 SB: External read register x0, Expected 0x00000000, Matches Actual 0x00000000`

### 1.9 — `sw_lw`

**Functionality:**  Value written by `sw` is correctly read back by later `lw` from the same address

**Initial state:**

- Registers:  reset state
- Data memory:  randomized by `init_memories()`
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1),  .rs1(0), .imm(103)),   // x1 = 0 + 103
  asm_instr(.op(OP_SW),   .rs1(0), .rs2(1), .imm(0)),     // dmem[0] = 103
  asm_instr(.op(OP_LW),   .rd(2),  .rs1(0), .imm(0)),     // x2 = 103
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h0000_0067` | `x0 (0) + 103` |
| `dmem[0]` | `32'h0000_0067` | `x1` |
| `x2` | `32'h0000_0067` | `dmem[0]` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2` differs from its reset value; data memory unchanged from pre-test randomized contents other than word `0`

**Final result:** Pass: `96665 SB: CPU store dmem[0x000] = 0x00000067, Matches Expected`
  `96755 SB: External read register x2, Expected 0x00000067, Matches Actual 0x00000067`

### 1.10 — `beq_taken_forward`

**Functionality:**  Correct instruction execution after branch is taken

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),    // addr 0:  x1 = 0 + 5
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(5)),    // addr 4:  x2 = 0 + 5
  asm_instr(.op(OP_BEQ), .rs1(1), .rs2(2), .imm(8)),    // addr 8:  jump to addr 8 + 8
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(6767)), // addr 12: must be skipped
  asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(1)),    // addr 16: x4 = 0 + 1
  EBREAK_WORD                                                         
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h0000_0005` | `x0 (0) + 5` |
| `x2` | `32'h0000_0005` | `x0 (0) + 5` |
| `x3` | `32'h0000_0000` | reset value |
| `x4` | `32'h0000_0001` | `x0 (0) + 1` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2`, `x4` differs from its reset value; data memory unchanged

**Final result:** Pass: `98215 SB: External read register x3, Expected 0x00000000, Matches Actual 0x00000000`    `98235 SB: External read register x4, Expected 0x00000001, Matches Actual 0x00000001`     

### 1.11 — `beq_taken_backward`

**Functionality:**  Sign extension of `imm` in branch instruction

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
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
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h0000_0005` | `x0 (0) + 5` |
| `x2` | `32'h0000_0005` | `x0 (0) + 5` |
| `x3` | `32'h0000_0007` | `x0 (0) + 7` |
| `x4` | `32'h0000_0007` | `x0 (0) + 7` |
| `x5` | `32'h0000_0000` | reset value |

**Pass criteria:** CPU halts via `ebreak` instruction at addr 12 within the timeout; values are as above; no register other than `x1`, `x2`, `x3`, `x4` differs from its reset value; data memory unchanged

**Final result:**  Pass: `99735 SB: External read register x3, Expected 0x00000007, Matches Actual 0x00000007`
     `99775 SB: External read register x5, Expected 0x00000000, Matches Actual 0x00000000`

### 1.12 — `beq_not_taken`

**Functionality:**  Sequential instruction execution after branch is not taken

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),    // addr 0:  x1 = 0 + 5
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(7)),    // addr 4:  x2 = 0 + 7
  asm_instr(.op(OP_BEQ), .rs1(1), .rs2(2), .imm(12)),   // addr 8:  5 != 7, branch not taken
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(1)),    // addr 12: x3 = 0 + 1
  EBREAK_WORD,                                          // addr 16: correct breakpoint
  asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(6767)), // addr 20: must not be executed
  EBREAK_WORD                                           // addr 24: safety
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h0000_0005` | `x0 (0) + 5` |
| `x2` | `32'h0000_0007` | `x0 (0) + 7` |
| `x3` | `32'h0000_0001` | `x0 (0) + 1` |
| `x4` | `32'h0000_0000` | reset value |

**Pass criteria:** CPU halts via `ebreak` instruction at addr 16 within the timeout; values are as above; no register other than `x1`, `x2`, `x3` differs from its reset value; data memory unchanged

**Final result:** Pass:  `101195 SB: External read register x3, Expected 0x00000001, Matches Actual 0x00000001` `101215 SB: External read register x4, Expected 0x00000000, Matches Actual 0x00000000`

### 1.13 — `read_after_write`

**Functionality:**  Instruction reading is correctly ordered across clock edge

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),   // x1 = 0 + 5
  asm_instr(.op(OP_ADD),  .rd(2), .rs1(1), .rs2(1)),   // x2 = 5 + 5
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h0000_0005` | `x0 (0) + 5` |
| `x2` | `32'h0000_000A` | `x1 + x1` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2` differs from its reset value; data memory unchanged

**Final result:** Pass:  `102535 SB: External read register x2, Expected 0x0000000a, Matches Actual 0x0000000a`

### 1.14 — `lw_use`

**Functionality:**  Stall-release timing for `lw` functions correctly

**Initial state:**

- Registers:  reset state
- Data memory:  randomized by init_memories()
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(103)),  // x1 = 103
  asm_instr(.op(OP_SW),  .rs1(0), .rs2(1), .imm(0)),    // dmem[0] = 103
  asm_instr(.op(OP_LW),   .rd(2), .rs1(0), .imm(0)),    // x2 = 103 
  asm_instr(.op(OP_ADD),  .rd(3), .rs1(2), .rs2(2)),    // x3 = 103 + 103
  EBREAK_WORD
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h0000_0067` | `x0 (0) + 103` |
| `dmem[0]` | `32'h0000_0067` | `x1` |
| `x2` | `32'h0000_0067` | `dmem[0]` |
| `x3` | `32'h0000_00CE` | `x2 + x2` |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2`, `x3` differs from its reset value; data memory unchanged from pre-test randomized contents other than word 0

**Final result:** Pass: `103985 SB: External read register x3, Expected 0x000000ce, Matches Actual 0x000000ce` 

### 1.15 — `ebreak_after_branch`

**Functionality:**  CPU halts branch and directs fetch to breakpoint

**Initial state:**

- Registers:  reset state
- Data memory:  none
- Other setup: none

**Program:**

```systemverilog
prog = '{
  asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(5)),    // addr 0:  x1 = 0 + 5
  asm_instr(.op(OP_ADDI), .rd(2), .rs1(0), .imm(5)),    // addr 4:  x2 = 0 + 5
  asm_instr(.op(OP_BEQ), .rs1(1), .rs2(2), .imm(8)),    // addr 8:  jump to addr 8 + 8 = 16
  asm_instr(.op(OP_ADDI), .rd(3), .rs1(0), .imm(6767)), // addr 12: must be skipped
  EBREAK_WORD                                           // addr 16: correct breakpoint
};
```

**Expected result:**

| Register or memory word | Expected value | Calculation or explanation |
| --- | --- | --- |
| `x1` | `32'h0000_0005` | `x0 (0) + 5` |
| `x2` | `32'h0000_0005` | `x0 (0) + 5` |
| `x3` | `32'h0000_0000` | reset value |

**Pass criteria:** CPU halts via `ebreak` within the timeout; values are as above; no register other than `x1`, `x2` differs from its reset value; data memory unchanged

**Final result:** Pass: `105395 SB: External read register x3, Expected 0x00000000, Matches Actual 0x00000000`

## 2. Constrained-random tests

### Instruction constraints

| Constraint | Behavior and purpose | Implementation |
| --- | --- | --- |
| `c_opcode` | Keeps `ebreak` and `nop` out of the randomized body; the sequencer appends the final `ebreak` | Opcode restricted to the arithmetic, memory, and branch set |
| `c_reg_bias` | Biases register selection 70% toward `x1`–`x7` so values are reused across instructions and dependencies occur often | Weighted `dist` on `rd`, `rs1`, `rs2` |
| `c_imm_range` | Limits `imm` to the 12-bit signed range used by I- and S-type instructions | `imm >= -2048 && imm <= 2047` |
| `c_mem_align` | Keeps `lw`/`sw` effective addresses word-aligned and inside data memory. An aligned `imm` is not enough: if `reg_snapshot[rs1]` is unaligned the effective address is too, so `reg_snapshot[rs1] + imm` as a whole must be a multiple of 4 and lie in `0`–`4092` (1024 4-byte words). `rs1` is left fully random rather than forced to a reserved register. | Constrain `reg_snapshot[rs1] + imm` to be word-aligned and within `0` to `4092` |
| `c_imm_unused` | Zeroes `imm` for register-only instructions | `imm == 0` for R-type ops |
| `c_branch_target` | Branch offsets are word multiples and strictly forward, so programs cannot loop, and stay within the program | `imm % 4 == 0`, `imm >= 4`, target `<= (prog_len - 1) * 4` |
| `c_no_branch_at_end` | Prevents `beq` in the last slot so a taken branch cannot jump past the final `ebreak` | No `beq` when `prog_len - idx < 2` |
| `c_branch_taken_bias` | Random registers rarely compare equal; biasing equality exercises both branch outcomes | `reg_snapshot[rs1] == reg_snapshot[rs2]` for `beq` 40% of the time |

### External-port constraints

| Constraint | Behavior and purpose | Implementation |
| --- | --- | --- |
| `c_align` | Keeps external-port addresses word-aligned | `addr[1:0] == 2'b00` |
| `c_valid_window` | Restricts accesses to the three mapped windows (instruction, data, register file) and register-file addresses to the 32 registers | Window in `{00, 01, 10}`; word index `0`–`31` for the register-file window |
| `c_reg_read_only` | The register file is read-only through the external port | No writes when targeting the register-file window |
| `c_data_corners` | Biases write data toward corner values | `32'h0000_0000`, `32'hFFFF_FFFF`, `32'h8000_0000` at 5% each; remaining 85% across the full range |

### Random-program test

| Item | Plan |
| --- | --- |
| Number of programs per seed | 20 |
| Program-length range | 5 to 50 |
| Information logged for reproduction | Numeric `SVSEED`, iteration, and complete generated program |

**Implementation outline:**

```systemverilog
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
```

## 3. Assertions

### Assertion summary

| Assertion ID/name | Behavior checked | When it is sampled/disabled | Activating test |
| --- | --- | --- | --- |
| 3.1 / `EXTERNAL_PORT_ONLY_WHEN_DISABLED` | External read and write occurs only when CPU is disabled | Sampled every `posedge clk`, disabled while `rst` is active | All tests |
| 3.2 / `SRAM_WINDOW_RESPONDS_NEXT_CYCLE` | One cycle after instruction or data SRAM read. request `rready` is high | Sampled every `posedge clk`, disabled while `rst` is active | Tests with external readback of instruction or data memory |
| 3.3 / `REG_WINDOW_RESPONDS_SAME_CYCLE` | In the same cycle as a register-file read request, `rready` is high | Sampled every `posedge clk`, disabled while `rst` is active | All tests |
| 3.4 / `CPU_RELEASES_AFTER_HALT` | Two cycles after `halt_cpu` or `cpu_halted`, `cpu_active` is low | Sampled every `posedge clk`, disabled while `rst` is active | All tests |
| 3.5 / `RESET_RELEASES_CPU` | One cycle after `rst` is high, `cpu_active` is low | Sampled every `posedge clk`, not disabled by `rst` | All tests |

### 3.1 — `EXTERNAL_PORT_ONLY_WHEN_DISABLED`

**Timing requirement in words:** At every clock edge the external port's read-enable and write-enable must be low whenever the CPU is active

```systemverilog
EXTERNAL_PORT_ONLY_WHEN_DISABLED:
    assert property (@(posedge clk) disable iff (rst)
        !(cpu_if.cpu_active && (cpu_if.w_en || cpu_if.r_en)))
    else assertion_fail("External port request (w_en/r_en) issued while CPU is active");
```

**Evidence that it detects a violation:** Forced `cpu_if.cpu_active = 1` then issued `xbar_write` to DMEM word 0 so that `w_en` is high while the CPU is active.
![EXTERNAL_PORT_ONLY_WHEN_DISABLED firing](<screenshots/Screenshot 2026-09-27 at 23.14.48-1.png>)
Passed with 0 assertion failures after the force was commented out (see "REVERTED ASSERTION VIOLATIONS" in `cpu_tb_top`)

### 3.2 — `SRAM_WINDOW_RESPONDS_NEXT_CYCLE`

**Timing requirement in words:**After a read request targets instruction or data SRAM, CPU is read-ready exactly one cycle later

```systemverilog
SRAM_WINDOW_RESPONDS_NEXT_CYCLE:
    assert property (@(posedge clk) disable iff (rst)
        (cpu_if.r_en && (cpu_if.addr[13:12] inside {2'b00, 2'b01})) |-> ##1 cpu_if.rready)
    else assertion_fail("SRAM window read did not respond on following cycle");
```

**Evidence that it detects a violation:** Forced `cpu_if.rready = 0` then read one word of DMEM so that SRAM read is not ready on the next cycle.
![SRAM_WINDOW_RESPONDS_NEXT_CYCLE firing](<screenshots/Screenshot 2026-09-27 at 23.16.46-1.png>)
Passed with 0 assertion failures after the force was commented out (see "REVERTED ASSERTION VIOLATIONS" in `cpu_tb_top`)

### 3.3 — `REG_WINDOW_RESPONDS_SAME_CYCLE`

**Timing requirement in words:**When a read request targets the register-file window, `rready` is high in that same cycle

```systemverilog
REG_WINDOW_RESPONDS_SAME_CYCLE:
    assert property (@(posedge clk) disable iff (rst)
        (cpu_if.r_en && cpu_if.addr[13:12] == 2'b10) |-> cpu_if.rready)
    else assertion_fail("Register-file window read did not respond in the same cycle");
```

**Evidence that it detects a violation:** Forced `cpu_if.rready = 0` then read back register x0 so that the register-file read is not ready in the same cycle
![REG_WINDOW_RESPONDS_SAME_CYCLE firing](<screenshots/Screenshot 2026-09-27 at 23.17.51-1.png>)
Passed with 0 assertion failures after the force was commented out (see "REVERTED ASSERTION VIOLATIONS" in `cpu_tb_top`)

### 3.4 — `CPU_RELEASES_AFTER_HALT`

**Timing requirement in words:**Two cycles after an external halt request or `ebreak`, CPU no longer controls memories

```systemverilog
CPU_RELEASES_AFTER_HALT:
    assert property (@(posedge clk) disable iff (rst)
        (cpu_if.halt_cpu || cpu_if.cpu_halted) |-> ##2 !cpu_if.cpu_active)
    else assertion_fail("CPU did not release memories two cycles after halt");
```

**Evidence that it detects a violation:** Forced `cpu_if.cpu_active = 1` then switched `halt_cpu = 1` for one cycle so that after 4 cycles CPU is still active even two cycles after halt request.
![CPU_RELEASES_AFTER_HALT firing](<screenshots/Screenshot 2026-09-27 at 23.19.31-1.png>)
Passed with 0 assertion failures after the force was commented out (see "REVERTED ASSERTION VIOLATIONS" in `cpu_tb_top`)

### 3.5 — `RESET_RELEASES_CPU`

**Timing requirement in words:**One cycle after reset is asserted, the CPU no longer controls memories

```systemverilog
RESET_RELEASES_CPU:
    assert property (@(posedge clk)
        rst |-> ##1 !cpu_if.cpu_active)
    else assertion_fail("CPU still active after reset");
```

**Evidence that it detects a violation:** Forced `cpu_if.cpu_active = 1` during `drv.reset_task()` so that CPU is still active even one cycle after reset
![RESET_RELEASES_CPU firing](<screenshots/Screenshot 2026-09-27 at 23.20.49-1.png>)
Passed with 0 assertion failures after the force was commented out (see "REVERTED ASSERTION VIOLATIONS" in `cpu_tb_top`)

## 4. Encrypted CPU Bug Hunt

### 4.1 — BEQ 1
### Random discovery

| Field                    | Evidence                      |
| ------------------------ | ----------------------------- |
| Discovery command        | `make bug_hunt SEED=random SIM_PLUSARGS=+NUM_RANDOM_PROGRAMS=100`   |
| Numeric `SVSEED`         | -144230556 |
| Failing iteration        |38                               |
| First failure message    | `2931195 SB: [random_prog_38] store to dmem[0x08e] = 0x00000000, expected dmem[0x039] = 0x00000000`                              |
| Reproduction command     | `make bug_hunt SEED=-144230556 SIM_PLUSARGS=+NUM_RANDOM_PROGRAMS=100` |
| Reproduces consistently? | Yes                      |

**Original failing program:**

```systemverilog
prog = '{
    32'h005310b3,  // [0] sll x1, x6, x5
    32'h3ac02c23,  // [1] sw x12, 952(x0)
    32'h28c9a383,  // [2] lw x7, 652(x19)
    32'h00431d33,  // [3] sll x26, x6, x4
    32'h00128263,  // [4] beq x5, x1, 4
    32'h71802183,  // [5] lw x3, 1816(x0)
    32'h02300e63,  // [6] beq x0, x3, 60 BUG HERE
    32'h004103b3,  // [7] add x7, x2, x4 SKIPPED STARTING HERE
    32'h5780a083,  // [8] lw x1, 1400(x1)
    32'h00400833,  // [9] add x16, x0, x4
    32'h0e43a223,  // [10] sw x4, 228(x7)
    32'h04138263,  // [11] beq x7, x1, 68
    32'h00219cb3,  // [12] sll x25, x3, x2
    32'h00729333,  // [13] sll x6, x5, x7
    32'h76032023,  // [14] sw x0, 1888(x6)
    32'h46432283,  // [15] lw x5, 1124(x6)
    32'h0012deb3,  // [16] srl x29, x5, x1
    32'h64732a23,  // [17] sw x7, 1620(x6)
    32'h002313b3,  // [18] sll x7, x6, x2
    32'h00300c63,  // [19] beq x0, x3, 24
    32'h00c11133,  // [20] sll x2, x2, x12 SKIPPED UNTIL HERE
    32'h0002d2b3,  // [21] srl x5, x5, x0 INCORRECT BRANCH SKIPS TO HERE
    32'h0033da33,  // [22] srl x20, x7, x3
    32'h003350b3,  // [23] srl x1, x6, x3
    32'hf9130393,  // [24] addi x7, x6, -111
    32'h002f8463,  // [25] beq x31, x2, 8
    32'h00318333,  // [26] add x6, x3, x3
    32'h406301b3,  // [27] sub x3, x6, x6
    32'h23f12c23,  // [28] sw x31, 568(x2)
    32'h00731133,  // [29] sll x2, x6, x7
    EBREAK_WORD    // [30] ebreak
};
```

### Expected vs. actual

| Instruction / event | Expected | Actual | Cycle/time |
| ------------------- | -------- | ------ | ---------- |
|`[5] lw x3, 1816(x0)`  | `x3 = dmem[0x1C6] (0x79f5eea3)`  | Matches expected | 2931105 |
|`[6] beq x0, x3, 60`  | Branch not taken since `x0 (0) != x3 (dmem[0x1C6] == 0x79f5eea3)` | Branch is taken, 14 instructions skipped | 2931115 |
|`[10], [14], [17] sw`  | Stores to `dmem[0x039]`, `dmem[0x1d8]`, `dmem[0x195]` | No stores | N/A |
|`[28] sw x31, 568(x2)`  | 5th store to `dmem` | 2nd store | 2931195 |

**First architectural divergence:**

Instruction 6 `beq x0, x3, 60` branch was taken even though the preceding `lw` loaded `x3 = 0x79f5eea3 != 0`.

### Minimization

**Minimized reproducer:**

```systemverilog
prog = '{
    asm_instr(.op(OP_ADDI), .rd(1), .rs1(0), .imm(6)),   // x1 = 0 + 6
    asm_instr(.op(OP_SW),  .rs1(0), .rs2(1), .imm(0)),   // dmem[0] = 6
    asm_instr(.op(OP_LW),   .rd(3), .rs1(0), .imm(0)),   // x3 = 6 (0 original value)
    asm_instr(.op(OP_BEQ), .rs1(3), .rs2(0), .imm(8)),   // 6 != 0 (branch must not be taken)
    asm_instr(.op(OP_ADDI), .rd(4), .rs1(0), .imm(1)),   // x4 = 1 (must be executed)
    EBREAK_WORD
};
```

### Waveform evidence

![Bug 1 waveform](<screenshots/waveform1.png>)

### Conclusion

**Trigger:** `beq` immediately after `lw` whose destination register is a `beq` source register

**Expected behavior:** `beq` compares the value loaded by `lw`

**Observed behavior:** `beq` uses the register's old value before the `lw` for comparison, leading to potentially incorrect branch or no branch 

**Separated nearby possibilities:** `nop` between `lw` and `beq` does not reproduce error, both `beq` operands suffer same behavior

**Behavioral characterization:** When a `beq` immediately follows an `lw` whose destination register is a `beq` source register, `beq` uses that register's value from before the load

### 4.2 — LW after SW
### Random discovery

| Field                    | Evidence                      |
| ------------------------ | ----------------------------- |
| Discovery command        | `make bug_hunt SIM_PLUSARGS=+NUM_RANDOM_PROGRAMS=100`   |
| Numeric `SVSEED`         | 1 |
| Failing iteration        |1                               |
| First failure message    | `253245 SB: [random_prog_1] read of register x5 returned 0xb021b3b8, expected 0x80d802ee`                              |
| Reproduction command     | `make bug_hunt SIM_PLUSARGS=+NUM_RANDOM_PROGRAMS=100` |
| Reproduces consistently? | Yes                      |

**Original failing program:**

```systemverilog
prog = '{
    32'h003892b3,  // [0] sll x5, x17, x3
    32'h39b22e23,  // [1] sw x27, 924(x4)
    32'h006387b3,  // [2] add x15, x7, x6
    32'h0003deb3,  // [3] srl x29, x7, x0
    32'h405e01b3,  // [4] sub x3, x28, x5
    32'h43eb2023,  // [5] sw x30, 1056(x22)
    32'h00215933,  // [6] srl x18, x2, x2
    32'h9bf38313,  // [7] addi x6, x7, -1601
    32'h62bc0193,  // [8] addi x3, x24, 1579
    32'h003101b3,  // [9] add x3, x2, x3
    32'h04328463,  // [10] beq x5, x3, 72
    32'h000bd8b3,  // [11] srl x17, x23, x0
    32'h7430a623,  // [12] sw x3, 1868(x1)
    32'h007a83b3,  // [13] add x7, x21, x7
    32'h35908113,  // [14] addi x2, x1, 857
    32'he4212ba3,  // [15] sw x2, -425(x2)
    32'h403005b3,  // [16] sub x11, x0, x3
    32'h01920c63,  // [17] beq x4, x25, 24
    32'h003350b3,  // [18] srl x1, x6, x3
    32'h002c1233,  // [19] sll x4, x24, x2
    32'h024e8063,  // [20] beq x29, x4, 32
    32'h7108a303,  // [21] lw x6, 1808(x17)
    32'h00438a63,  // [22] beq x7, x4, 20
    32'h21912da3,  // [23] sw x25, 539(x2)
    32'hd4c127a3,  // [24] sw x12, -689(x2)
    32'h77d32183,  // [25] lw x3, 1917(x6)
    32'h000190b3,  // [26] sll x1, x3, x0
    32'h7ed32283,  // [27] lw x5, 2029(x6)
    32'h242125a3,  // [28] sw x2, 587(x2)
    32'h00600c33,  // [29] add x24, x0, x6
    32'h68532aa3,  // [30] sw x5, 1685(x6) STORE TO dmem[0x15]
    32'h2d43a283,  // [31] lw x5, 724(x7) BUG HERE
    32'h400003b3,  // [32] sub x7, x0, x0
    32'h62cb8093,  // [33] addi x1, x23, 1580
    32'h00700c63,  // [34] beq x0, x7, 24
    32'h5786a303,  // [35] lw x6, 1400(x13)
    32'h007c0a63,  // [36] beq x24, x7, 20
    32'h6cd32283,  // [37] lw x5, 1741(x6)
    32'h40538133,  // [38] sub x2, x7, x5
    32'h004092b3,  // [39] sll x5, x1, x4
    32'h3d47ac03,  // [40] lw x24, 980(x15)
    32'ha3910013,  // [41] addi x0, x2, -1479
    32'h766322a3,  // [42] sw x6, 1893(x6)
    32'h40938333,  // [43] sub x6, x7, x9
    32'h0042dd33,  // [44] srl x26, x5, x4
    EBREAK_WORD    // [45] ebreak
};

```

### Expected vs. actual

| Instruction / event | Expected | Actual | Cycle/time |
| ------------------- | -------- | ------ | ---------- |
|`[30] sw x5, 1685(x6)`  | Write `0xb021b3b8` to `dmem[0x015]`  | Matches expected | 222245 |
|`[31] lw x5, 724(x7)`  |`x5 = dmem[0x0b5] (0x80d802ee)` | `x5 = 0xb021b3b8` | 222275 |

**First architectural divergence:**

Instruction 31 `lw x5, 724(x7)` wrote `x5 = 0xb021b3b8` (the value just stored in `0x015` in memory) instead loading the value at `0x0b5` in memory, `0x80d802ee`

### Minimization

**Minimized reproducer:**

```systemverilog
prog = '{
    asm_instr(.op(OP_SW),   .rs1(5), .rs2(0),  .imm(344)),  // dmem[86] = 0
    asm_instr(.op(OP_LW),   .rd(4),  .rs1(17), .imm(280)),  // x4 = dmem[70]
    EBREAK_WORD
};
```

### Waveform evidence

![Bug 2 waveform](<screenshots/Screenshot 2026-09-30 at 20.54.33.png>)

### Conclusion

**Trigger:** `sw` immediately followed by `lw` to a different address in memory whose lowest 4 bits match the address stored to by `sw`

**Expected behavior:** `lw` writes the value stored at its address

**Observed behavior:** `lw` writes the value the preceding `sw` just stored into its destination register

**Separated nearby possibilities:** Differences in the lowest 4 bits do not trigger bug, but differences in only bits 4 and above do, `nop` in between `sw` and `lw` does not trigger bug

**Behavioral characterization:** When an `lw` immediately follows an `sw` and their word addresses match in the lowest 4 bits, the register is loaded with the data stored by `sw` instead of data at the load address

### 4.3 — BEQ 2
### Random discovery

| Field                    | Evidence                      |
| ------------------------ | ----------------------------- |
| Discovery command        | `make bug_hunt SEED=random SIM_PLUSARGS=+NUM_RANDOM_PROGRAMS=100`   |
| Numeric `SVSEED`         | 1301401590 |
| Failing iteration        |45                               |
| First failure message    | `3476565 SB: [random_prog_45] read of register x5 returned 0x00000000, expected 0x0007ffff`                              |
| Reproduction command     | `make bug_hunt SEED=1301401590 SIM_PLUSARGS=+NUM_RANDOM_PROGRAMS=100` |
| Reproduces consistently? | Yes                      |

**Original failing program:**

```systemverilog
prog = '{
    32'hc0310193,  // [0] addi x3, x2, -1021
    32'h00018233,  // [1] add x4, x3, x0
    32'h001992b3,  // [2] sll x5, x19, x1
    32'h00118233,  // [3] add x4, x3, x1
    32'h00500c63,  // [4] beq x0, x5, 24
    32'h50d18193,  // [5] addi x3, x3, 1293
    32'h0000d133,  // [6] srl x2, x1, x0
    32'h00335633,  // [7] srl x12, x6, x3
    32'h1842a103,  // [8] lw x2, 388(x5)
    32'h4ae18313,  // [9] addi x6, x3, 1198
    32'h005903b3,  // [10] add x7, x18, x5
    32'h004c0033,  // [11] add x0, x24, x4
    32'h3035a023,  // [12] sw x3, 768(x11)
    32'hc2d28213,  // [13] addi x4, x5, -979
    32'h48102c23,  // [14] sw x1, 1176(x0)
    32'h004d03b3,  // [15] add x7, x26, x4
    32'h404103b3,  // [16] sub x7, x2, x4
    32'h00721533,  // [17] sll x10, x4, x7
    32'h180da383,  // [18] lw x7, 384(x27)
    32'h003090b3,  // [19] sll x1, x1, x3
    32'h02338c63,  // [20] beq x7, x3, 56
    32'h00521133,  // [21] sll x2, x4, x5
    32'h000351b3,  // [22] srl x3, x6, x0
    32'h00d290b3,  // [23] sll x1, x5, x13
    32'h024c0663,  // [24] beq x24, x4, 44
    32'h02120063,  // [25] beq x4, x1, 32
    32'h005316b3,  // [26] sll x13, x6, x5
    32'h40600233,  // [27] sub x4, x0, x6
    32'h000ad0b3,  // [28] srl x1, x21, x0
    32'h40430333,  // [29] sub x6, x6, x4
    32'h1f442383,  // [30] lw x7, 500(x8)
    32'h00a08463,  // [31] beq x1, x10, 8 BUG HERE
    32'h002152b3,  // [32] srl x5, x2, x2 SKIPPED
    32'h00c300b3,  // [33] add x1, x6, x12
    32'h7e41a423,  // [34] sw x4, 2024(x3)
    32'h02300063,  // [35] beq x0, x3, 32
    32'h000293b3,  // [36] sll x7, x5, x0
    32'h00300433,  // [37] add x8, x0, x3
    32'h0015a823,  // [38] sw x1, 16(x11)
    32'h64012ba3,  // [39] sw x0, 1623(x2)
    32'h3241a003,  // [40] lw x0, 804(x3)
    32'h00028033,  // [41] add x0, x5, x0
    32'h3a432023,  // [42] sw x4, 928(x6)
    32'h403e0333,  // [43] sub x6, x28, x3
    32'h4260a623,  // [44] sw x6, 1068(x1)
    32'ha5920193,  // [45] addi x3, x4, -1447
    EBREAK_WORD    // [46] ebreak
};
```

### Expected vs. actual

| Instruction / event | Expected | Actual | Cycle/time |
| ------------------- | -------- | ------ | ---------- |
|`[31] beq x1, x10, 8`  | Branch not taken since `x1 (0) != x10 (0xe1680000)`  | Branch taken, #33 next instruction| 3445605 |
|`[32] srl x5, x2, x2`  | `x5 = 0x0007ffff (0xfffffc2d >> 13 (01101))` | Instruction skipped | N/A |

**First architectural divergence:**

Instruction 31 `beq x1, x10, 8` branch was taken even though `x1 = 0` and `x10 = 0xe1680000`

### Minimization

**Minimized reproducer:**

```systemverilog
prog = '{
    asm_instr(.op(OP_ADDI), .rd(1),  .rs1(0),  .imm(256)),   // x1 = [23 0s]1_0000_0000
    asm_instr(.op(OP_BEQ),  .rs1(0), .rs2(1),  .imm(8)),     // ...0_0000_0000 != ...1_0000_0000 (branch not taken)
    asm_instr(.op(OP_ADDI), .rd(2),  .rs1(0),  .imm(67)),    // x2 = 67 (must be executed)
    EBREAK_WORD
};
```

### Waveform evidence

![Bug 3 waveform](<screenshots/Screenshot 2026-09-30 at 21.28.55.png>)

### Conclusion

**Trigger:** `beq` with source registers with the same lowest 8 bits and different [31:8] bits

**Expected behavior:** `beq` branch is taken only if all 32 bits of `rs1` and `rs2` are equal

**Observed behavior:** `beq` branch is taken even though `x1 == 0 != x10 == 0xe1680000`  

**Separated nearby possibilities:** Differences in the lowest 8 bits do not trigger bug, but differences in only bits 8 and above do

**Behavioral characterization:** `beq` decides equality by comparing only the lowest 8 bits of the source registers, so registers equal in bits [7:0] but different in [31:8] are still considered equal 

