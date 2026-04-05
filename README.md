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

