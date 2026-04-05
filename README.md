# Single-Cycle RISC-V Processor (RV32I) — Verilog

A fully functional single-cycle RISC-V processor implemented in Verilog, supporting the complete RV32I Base Integer Instruction Set (excluding `ecall` and `ebreak`). The design uses a **6-stage FSM-based execution model** with a clean memory-mapped bus interface.

> Developed as part of the **DAC102 Computer Architecture** course project @IIT Roorkee.

---

## Architecture Overview

The processor is built around a 6-stage Finite State Machine:

```
FETCH → DECODE → EXEC → MEM_RD → MEM_WAIT → MEM_WR
```

| Stage      | Description |
|------------|-------------|
| `FETCH`    | Asserts `mem_rstrb` and places PC on `mem_addr` |
| `DECODE`   | Waits for `mem_rbusy` to deassert, latches instruction from `mem_rdata` |
| `EXEC`     | Decodes instruction, computes ALU result, determines next PC |
| `MEM_RD`   | Asserts `mem_rstrb` for load instructions |
| `MEM_WAIT` | Waits for `mem_rbusy`, writes loaded value to register file |
| `MEM_WR`   | Waits for `mem_wbusy` to deassert before advancing PC |

---

## Supported Instructions

| Category       | Instructions |
|----------------|--------------|
| **R-type**     | `add`, `sub`, `xor`, `or`, `and`, `sll`, `srl`, `sra`, `slt`, `sltu` |
| **I-type ALU** | `addi`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai`, `slti`, `sltiu` |
| **Load**       | `lb`, `lh`, `lw`, `lbu`, `lhu` |
| **Store**      | `sb`, `sh`, `sw` |
| **Branch**     | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| **Jump**       | `jal`, `jalr` |
| **Upper Imm**  | `lui`, `auipc` |

---

## Module Overview

Everything is implemented in a **single monolithic module** — `riscv_processor` — for simplicity. Key internal components include:

- **Immediate Generator** — decodes I/S/B/U/J immediate formats
- **ALU** — 11-operation ALU (add/sub/and/or/xor/sll/srl/sra/slt/sltu/passB)
- **Branch Logic** — combinational block evaluating all 6 branch conditions
- **Load Extractor** — sign/zero-extends byte and halfword loads
- **Store Formatter** — replicates data across byte lanes, computes `mem_wmask`
- **Register File** — 32×32-bit registers; `x0` hardwired to zero

---

## Testbench Overview

The `test benches/` directory contains **12 testbench files** split into two groups: focused unit tests (`tb1`–`tb7`, `riscv_tb`, `riscv_testbench_1`) and larger combined testbenches (`TB_1`–`TB_3`) written alongside a coursework partner.

---

### Focused Unit Testbenches

#### `riscv_tb.v` — Comprehensive Single-Pass Test
The main catch-all testbench. Runs **12 sequential test tasks** in one shot covering the full RV32I instruction set:

| # | Task | What it tests |
|---|------|---------------|
| 1 | Arithmetic | `ADD`, `SUB`, `ADDI` — basic integer ops |
| 2 | Logical | `AND`, `OR`, `XOR`, `ANDI`, `ORI`, `XORI` |
| 3 | Shifts | `SLL`, `SRL`, `SRA`, `SLLI`, `SRLI`, `SRAI` — including sign extension |
| 4 | SLT | `SLT`, `SLTU`, `SLTI`, `SLTIU` — signed and unsigned comparisons |
| 5 | Upper Imm | `LUI`, `AUIPC` — 20-bit immediate loading and PC-relative addressing |
| 6 | Jumps | `JAL`, `JALR` — forward jumps and return address saving |
| 7 | Branches | `BEQ`, `BNE`, `BLT`, `BGE` — taken and not-taken cases |
| 8 | Load/Store | `LW`, `SW` — 32-bit word read/write roundtrip |
| 9 | Byte/Half | `SB`, `SH`, `LB`, `LH`, `LBU`, `LHU` — sign and zero extension |
| 10 | Loop | Backward branch loop — sum 1 to 5 = 15 |
| 11 | Unsigned Branches | `BLTU`, `BGEU` — unsigned boundary comparison |
| 12 | Negatives | Negative arithmetic — `-5 + (-3)`, `-5 - (-3)` |

---

#### `tb1_alu_arithmetic.v` — ALU Arithmetic Corner Cases
**8 sub-tests** targeting edge cases of `ADD`, `SUB`, and `ADDI`:

| Sub-test | What it tests |
|----------|---------------|
| 1a | Signed overflow: `0x7FFFFFFF + 1 = 0x80000000` |
| 1b | Signed underflow: `0x80000000 - 1 = 0x7FFFFFFF` |
| 1c | ADD with x0: result unchanged |
| 1d | SUB to zero: `90 - 90 = 0` |
| 1e | Chained ADDI: `10+20+30+40+50 = 150` |
| 1f | x0 hardwired: writes to `x0` silently discarded |
| 1g | Large negative ADDI: `10 + (-2048) = -2038` |
| 1h | Self-subtraction: `x - x = 0` for any value |

---

#### `tb2_branch_stress.v` — Branch Instruction Stress Test
**6 sub-tests** exhaustively testing all 6 branch types, including edge cases:

| Sub-test | What it tests |
|----------|---------------|
| 1 | `BEQ` — taken (5==5) and not taken (5≠3) |
| 2 | `BNE` — taken (10≠7) and not taken (10==10) |
| 3 | `BLT` / `BGE` — with negative numbers (`-5 < 3`) |
| 4 | `BLTU` / `BGEU` — unsigned boundary (`0` vs `0xFFFFFFFF`) |
| 5 | Backward branch — countdown loop from 5 to 0 |
| 6 | `BEQ x0, x0` — always-taken branch |

---

#### `tb3_load_store_variants.v` — Load/Store Width Variants
**7 sub-tests** covering all load and store widths with sign/zero extension:

| Sub-test | What it tests |
|----------|---------------|
| 1 | `SW` / `LW` roundtrip |
| 2 | `LB` sign extension: `0x80` → `0xFFFFFF80` |
| 3 | `LBU` zero extension: `0x80` → `0x00000080` |
| 4 | `LH` sign extension: `0x8000` → `0xFFFF8000` |
| 5 | `LHU` zero extension: `0x8000` → `0x00008000` |
| 6 | `SB` + `SH` composite write, verified by `LW` |
| 7 | Load into `x0` discarded — result stays 0 |

---

#### `tb4_shift_logic.v` — Shift and Logic Instructions
Covers `SLL`, `SRL`, `SRA`, `SLLI`, `SRLI`, `SRAI`, `AND`, `OR`, `XOR` and their immediate variants. Tests both positive and negative operands to verify arithmetic vs. logical right shift behaviour.

---

#### `tb5_jump_link.v` — JAL / JALR and Link Register
**5 sub-tests** focused on jump behaviour and return address correctness:

| Sub-test | What it tests |
|----------|---------------|
| 1 | `JAL` saves `PC+4` as return address |
| 2 | `JALR` with register + offset (`jalr x2, 8(x1)`) |
| 3 | `JAL x0` — unconditional jump with no link |
| 4 | Function call-and-return pattern using `jalr x0, 0(ra)` |
| 5 | `JALR` clears the LSB of the target address per spec |

---

#### `tb6_upper_imm_slt.v` — LUI / AUIPC / SLT variants
**7 sub-tests** covering upper-immediate instructions and all set-less-than forms:

| Sub-test | What it tests |
|----------|---------------|
| 1 | `LUI` — loads 20-bit immediate into upper bits |
| 2 | `LUI` + `ADDI` — constructs a full 32-bit constant (`0xDEADBEEF`) |
| 3 | `AUIPC` — at three different PCs to verify PC-relative result |
| 4 | `SLT` signed — `-5 < 3 = 1`, `3 < -5 = 0` |
| 5 | `SLTU` unsigned — `1 < 0xFFFFFFFF`, `0xFFFFFFFF < 1` |
| 6 | `SLTI` / `SLTIU` — immediate variants, 4 checks |
| 7 | `LUI x0` — write to `x0` discarded |

---

#### `tb7_programs.v` — Full Program Integration Tests
**5 realistic multi-instruction programs** that exercise the processor as a whole:

| Program | What it runs |
|---------|-------------|
| Fibonacci | Computes `fib(10) = 55` using a loop |
| Power of 2 | Computes `2^10 = 1024` by repeated doubling |
| Array sum | Initializes `{10,20,30,40,50}` in memory, sums to 150 |
| Memory copy | Copies 4 words from source to destination region |
| Register stress | Loads `x1–x10 = 1–10`, sums all to `55` across 9 `ADD` instructions |

---

### Combined Testbenches (`TB_1`, `TB_2`, `TB_3`)

These are larger testbenches written collaboratively, each running a complete suite against the processor:

| File | Tests | Coverage |
|------|-------|---------|
| `TB_1.v` | 23 individual tests | Full RV32I: all R/I/S/B/U/J instructions, loops, load/store patterns, `x0` invariant |
| `TB_2.v` | Extended coverage | Additional load/store, branch, and `LUI`/`AUIPC` edge cases |
| `TB_3.v` | Comprehensive stress | Largest suite — includes long programs, chained operations, and boundary values |

> `TB_1`, `TB_2`, and `TB_3` are self-contained and do not depend on `tb1`–`tb7`.

---

## Getting Started

### Prerequisites

- [iVerilog](https://steveicarus.github.io/iverilog/) — for simulation
- [GTKWave](http://gtkwave.sourceforge.net/) — optional, for waveform viewing

### Running Testbenches

All testbenches are in the `test benches/` directory. Run them individually with:

```bash
# Basic smoke test
iverilog -o out riscv.v "test benches/riscv_tb.v" && vvp out

# ALU arithmetic
iverilog -o out riscv.v "test benches/tb1_alu_arithmetic.v" && vvp out

# Branch stress test
iverilog -o out riscv.v "test benches/tb2_branch_stress.v" && vvp out

# Load/store variants
iverilog -o out riscv.v "test benches/tb3_load_store_variants.v" && vvp out

# Shift and logic
iverilog -o out riscv.v "test benches/tb4_shift_logic.v" && vvp out

# Jump and link
iverilog -o out riscv.v "test benches/tb5_jump_link.v" && vvp out

# Upper immediate and SLT
iverilog -o out riscv.v "test benches/tb6_upper_imm_slt.v" && vvp out

# Programs
iverilog -o out riscv.v "test benches/tb7_programs.v" && vvp out
```

For the larger combined testbenches (TB_1, TB_2, TB_3):

```bash
iverilog -o tb1 riscv.v "test benches/TB_1.v" && vvp tb1
iverilog -o tb2 riscv.v "test benches/TB_2.v" && vvp tb2
iverilog -o tb3 riscv.v "test benches/TB_3.v" && vvp tb3
```

---

## Design Notes

- **Reset** is active-low — hold `reset = 0` to reset, release to `1` to run.
- **x0** is hardwired to zero; writes to `x0` are silently discarded.
- **JALR** clears the LSB of the computed target address per the RISC-V spec.
- **Store** instructions wait for `mem_wbusy` to deassert before advancing PC.
- **Load/store byte writes** replicate the byte across all lanes of `mem_wdata`; `mem_wmask` selects the correct byte(s).
- **AUIPC** passes PC as ALU operand A instead of a register value.

---

## File Structure

```
.
├── riscv.v                # Main processor implementation (single module)
├── test benches/
│   ├── riscv_tb.v         # General smoke test
│   ├── riscv_testbench_1.v
│   ├── TB_1.v             # Combined testbench 1
│   ├── TB_2.v             # Combined testbench 2
│   ├── TB_3.v             # Combined testbench 3 (comprehensive)
│   ├── tb1_alu_arithmetic.v
│   ├── tb2_branch_stress.v
│   ├── tb3_load_store_variants.v
│   ├── tb4_shift_logic.v
│   ├── tb5_jump_link.v
│   ├── tb6_upper_imm_slt.v
│   └── tb7_programs.v
└── README.md
```

---

