# 5-Stage Pipelined RV64I-Subset Processor

A 64-bit pipelined processor implemented in Verilog and simulated in **Xilinx Vivado XSim**. The design is organized around a five-stage `IF → ID → EX → MEM → WB` datapath, with particular attention to the load/store path, pipeline hazards, forwarding, and branching. This is designed, integrated and debugged by me with assistance from Claude and ChatGPT for design discussion, code review, debugging help, iterations and for drafts of some modules and the testbenches.

> **Scope:** This is an RV64I-subset implementation. The supported and verified instruction scope is listed separately below. Further validation and refinements are ongoing.

## 1. Architecture:

```text
pcounter → instr_mem.instruction → IF_ID
                                  ↓
                 cu + imm_gen + reg_file
                                  ↓
                                ID_EX
                                  ↓
          hazard_forward → operand/store-data muxes
                                  ↓
                    main_ALU: result / flags
                                  ↓
                                EX_MEM
                                  ↓
          store_load_module ↔ data_memory → load_extract
                                  ↓
                                MEM_WB
                                  ↓
                     which_data → reg_file
```

The core uses four inter-stage registers:

- **`IF_ID[95:0]`** — fetched PC and 32-bit instruction.
- **`ID_EX[285:0]`** — source/destination register indices, control signals, `funct3`, PC, register operands, and immediate.
- **`EX_MEM[220:0]`** — memory/writeback controls, destination, ALU result, branch redirect control and target, flags, and forwarded store data.
- **`MEM_WB[135:0]`** — register-write controls, destination, memory-read data, and ALU result.

## 2. RTL modules:

### `core.v` — top-level integration

Connects the PC, instruction memory, decoder, immediate generator, register file, forwarding logic, ALU, data memory, load extractor, and pipeline registers.

Key internal signals:

- `instruction`, `if_id_instr`, `if_id_pc`: instruction fetch and IF/ID contents.
- `RegWrite`, `imm_or_reg_select`, `data_mem_read_en`, `data_mem_write_en`, `alu_control`, `branch`, `jal`, `jalr`: decode/control outputs.
- `regVSimm1`, `regVSimm2`: forwarded source operands; `regVSimm` selects the ALU's register/immediate B operand.
- `result`, `N`, `Z`, `C`, `V`, `branch_cond_ok`: ALU result, flags, and branch condition.
- `stall`: load-use interlock from the ID/EX load destination and the source registers used by the IF/ID instruction.
- `pc_mux_control`, `new_pc`: redirect control and computed target, pipelined through EX/MEM for the PC update.
- `which_data`: writeback selection between `mem_wb_mem_data` and `mem_wb_alu_result`, controlled by `mem_wb_data_mem_or_from_alu`.

The pipeline control inserts bubbles by clearing the ID/EX control signals on a load-use stall or branch resolution, and places a NOP in IF/ID during the branch/registered-redirect handling path.

### `pc.v` — program counter

**Inputs:** `clk`, `rst`, `from_mux`, `pc_mux_control`, `stall`. **Output:** `pc`.

At each rising edge: reset sets `pc=0`; otherwise a redirect loads `from_mux`; otherwise a stall holds `pc`; otherwise the PC advances by four. Priority is **reset → redirect → stall → `PC + 4`**.

### `instr_mem.v` — instruction fetch

**Input:** `pc`. **Output:** `instruction = instr_mem_256[pc[9:2]]`.

Stores 256 32-bit words. `pc[9:2]` indexes a word because instructions are addressed on 4-byte boundaries in this design.

### `cu.v` — instruction decoder and ALU control

**Input:** `instruction`. **Outputs:** `RegWrite`, `imm_or_reg_select`, `data_mem_read_en`, `data_mem_write_en`, `alu_control[3:0]`, `data_mem_or_from_alu`, `branch`, `jal`, `jalr`.

The opcode selects the instruction class and primary controls. `alu_op` then selects forced ADD (address generation), SUB (branch comparison), R-type decode from `funct3/funct7`, or I-type ALU decode from `funct3/funct6`. Unsupported opcodes receive inactive control defaults.

### `imm_gen.v` — immediate construction

**Input:** `instruction`. **Output:** 64-bit `immediate`.

Builds sign-extended I-, S-, and B-type immediates and U-/J-type immediate values from their separated instruction fields. R-type/other instructions produce zero because they do not use an immediate.

### `reg_file.v` — architectural registers

**Inputs:** `clk`, `rst`, `RegWrite`, `read_reg1`, `read_reg2`, `write_reg`, `write_data`. **Outputs:** `read_data1`, `read_data2`.

Contains 32 × 64-bit registers. Reads are combinational. Writes and reset are synchronous; writes to `x0` are blocked, and reads of `x0` return zero. A combinational writeback bypass returns `write_data` when a read address matches the current nonzero write address.

### `main_ALU.v` — execution and branch comparison

**Inputs:** 64-bit `A`, `B`, `alu_control[3:0]`, and `funct3`. **Outputs:** 64-bit `result`, flags `N/V/C/Z`, and `branch_cond_ok`.

Implements ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, and SLTU operations. Shift amounts use `B[5:0]`. For branches, `funct3` selects equality/inequality or signed/unsigned comparison from the ALU flags.

### `hazard_forward.v` — operand and store-data forwarding

**Inputs:** ID/EX source indices, EX/MEM and MEM/WB destination indices and `RegWrite` signals, plus `id_ex_data_mem_write_en`. **Outputs:** `AmuxSel`, `BmuxSel`, `SmuxSel`.

Each selector is one-hot encoded: `001` selects the ID/EX operand, `010` selects the EX/MEM ALU result, and `100` selects MEM/WB `which_data`. EX/MEM matches take priority over MEM/WB matches. `SmuxSel` performs the analogous selection for store data, only when the ID/EX instruction is a store.

### `store_load_module.v` — store address/lane preparation

**Inputs:** ALU byte address `result`, `funct3`, `data_toBeStored`, and `opcode_bit`. **Outputs:** `modified_address`, `modifiedDataSTORE`, `byte_enable[7:0]`.

- `modified_address = result >> 3` converts a byte address into a 64-bit word index.
- `result[2:0]` selects the byte lane; explicit 6-bit shift amounts align 8-, 16-, or 32-bit store data within the 64-bit word.
- `byte_enable` selects the written lane(s): 1 bit for SB, 2 for SH, 4 for SW, and `8'hFF` for SD.
- `opcode_bit` gates the store-data/mask outputs for store instructions.

### `data_memory.v` — 64-bit data RAM

**Inputs:** `clk`, `write_enable`, `read_enable`, `byte_enable[7:0]`, word-index `address`, and `write_data`. **Output:** `read_data`.

Contains 512 × 64-bit words (4 KiB). Reads are combinational when `read_enable && !write_enable`. Writes occur on the rising clock edge when `write_enable && !read_enable`; each asserted `byte_enable[i]` writes `write_data[i*8 +: 8]` into the corresponding byte lane.

### `load_extract.v` — load alignment and sign extension

**Inputs:** 64-bit `data_toBeLoaded`, `funct3`, and `addr_offset[2:0]`. **Output:** 64-bit `modifiedDataLOAD`.

Uses explicit 6-bit shift amounts to move the addressed byte/halfword/word to bit 0, masks to the requested width, and then sign-extends LB (8→64), LH (16→64), and LW (32→64). LD returns all 64 input bits unchanged. Unsupported `funct3` values return zero.

## 3. Memory access assumptions

The address calculated by the ALU is a **byte address**; the store/load module and data RAM interface use a **64-bit word index**. The low three address bits identify a lane within the word. The implemented halfword, word, and doubleword paths assume naturally aligned accesses; misaligned accesses spanning two 64-bit words and architectural misalignment exceptions are not implemented.

The RTL uses hard-coded file paths in instr_mem.v and data_memory.v to initialize memories via $readmemb in Vivado.

## 4. Instruction and operation map

The RTL contains the following operation paths. The recorded test coverage is listed in the Verification section.

| Instruction class | Operations represented in RTL | Notes |
|---|---|---|
| R-type integer ALU | `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA`, `SLT`, `SLTU` | Selected using `funct3` and `funct7`. |
| I-type integer ALU | `ADDI`, `ANDI`, `ORI`, `XORI`, `SLLI`, `SRLI`, `SRAI`, `SLTI`, `SLTIU` | Immediate shifts use the RV64 six-bit shift amount fields. |
| Loads | `LB`, `LH`, `LW`, `LD` | `LB`, `LH`, and `LW` are sign-extending; `LD` returns the full 64-bit word. |
| Stores | `SB`, `SH`, `SW`, `SD` | Store width selects the corresponding byte-enable mask and byte lanes. |
| Conditional branches | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` | `funct3` selects equality, inequality, signed, or unsigned comparison logic. |
| Additional decoded classes | `JAL`, `JALR`, `LUI`, `AUIPC` | Decode/immediate-generation cases exist, but complete end-to-end execution is not established by the recorded tests. |

### Scope limitations

- Unsigned loads `LBU`, `LHU`, and `LWU` are not implemented in `load_extract.v`.
- The recorded tests directly exercise only a subset of the operations listed above. See the test matrix below for what has actually been simulated and checked.
- Does not support `JAL`, `JALR`, `LUI`, or `AUIPC` yet. 
- The M/A/C/F/D extensions, CSR/system instructions, privilege modes, interrupts, architectural exceptions, and complete RV64I compliance are outside the demonstrated scope.

## 5. Verification

- `verification/15_instr_test/` — 15 instruction program with equivalent assembly instructions, testbench used and recorded console results.
- `verification/27_instr_test/` — 27 instruction program with equivalent assembly instructions, testbench used and recorded console results.

The testbenches construct reference results and check writeback/store event ordering, control flow, PC transitions, register state, and memory state and are created using ChatGPT. The recorded results are for the runs documented above;

## Repository layout

```text
rtl/                         Verilog processor modules
verification/15_instr_test/  Directed integration program, testbench, results
verification/27_instr_test/  Loop-based integration program, testbench, results
DataOperatedOn.txt           The three 64 bit data used for the text (in Data Memory)
README.md                    Architecture, signal-level module notes, scope, and tests
```
