# TG68K SuperScalar 4-Issue Architecture

## Overview

This document describes the redesigned TG68K processor core as a **4-issue superscalar** architecture. The new design can fetch, decode, and potentially execute **up to 4 instructions per clock cycle**, providing significant performance improvements over the original single-issue design.

## Architecture Highlights

- **4-wide fetch**: Fetches 4 instructions per cycle (64 bits from memory)
- **4-way parallel decode**: Decodes 4 instructions simultaneously
- **Out-of-order execution**: Instructions can execute as soon as operands are ready
- **In-order commit**: Results are committed in program order via Reorder Buffer
- **4 execution units**: 2 ALUs, 1 Load/Store Unit, 1 Branch Unit
- **Register renaming**: 64 physical registers mapped to 16 architectural registers
- **Reservation stations**: 16-entry buffer for instructions awaiting execution
- **Reorder buffer**: 32-entry buffer for tracking in-flight instructions

## Pipeline Stages

### 1. Instruction Fetch (IF)
- **File**: `TG68K_InstructionFetch.vhd`
- Fetches 4 instructions per cycle (64 bits) from memory
- Maintains fetch buffer with 4 instruction slots
- Supports branch prediction and pipeline flush on misprediction
- Stalls when ROB or RS are full

### 2. Instruction Decode (ID)
- **File**: `TG68K_Decode.vhd`
- Decodes 4 instructions in parallel
- Identifies instruction type (MOVE, ADD, SUB, AND, OR, branches, etc.)
- Determines which execution unit is needed
- Extracts source/destination registers and immediate values
- Detects load/store and branch instructions

### 3. Register Rename (RN)
- **File**: `TG68K_RegisterRename.vhd`
- Maps 16 architectural registers to 64 physical registers
- Eliminates WAW (Write-After-Write) and WAR (Write-After-Read) hazards
- Maintains Register Allocation Table (RAT)
- Manages free list of physical registers
- Supports checkpoint/restore for branch misprediction recovery

### 4. Dispatch (DIS)
- Instructions are dispatched to:
  - **Reorder Buffer (ROB)**: Allocates ROB entry for tracking
  - **Reservation Stations (RS)**: Holds instruction until operands ready

### 5. Issue (IS)
- **File**: `TG68K_ReservationStation.vhd`
- Monitors reservation stations for ready instructions
- Issues up to 4 instructions per cycle (one per execution unit)
- Implements wake-up logic for operand availability
- Performs operand forwarding from execution units

### 6. Execute (EX)
- **File**: `TG68K_ExecutionUnit.vhd`
- **4 Execution Units**:
  - **EU0 (ALU0)**: General arithmetic (ADD, SUB, MOVE, MOVEQ)
  - **EU1 (ALU1)**: Logical operations (AND, OR, EOR, shifts)
  - **EU2 (LSU)**: Load/Store operations
  - **EU3 (Branch)**: Branch resolution and address calculation
- Variable execution latencies:
  - ALU operations: 1 cycle
  - Memory operations: 2+ cycles
  - Branches: 1 cycle

### 7. Writeback (WB)
- Execution units broadcast results to:
  - Reservation stations (for dependent instructions)
  - Reorder buffer (mark instruction complete)
  - Physical register file (for forwarding)

### 8. Commit (COM)
- **File**: `TG68K_ReorderBuffer.vhd`
- Commits up to 4 instructions per cycle **in program order**
- Ensures precise exceptions
- Frees old physical registers
- Detects branch mispredictions
- Flushes pipeline on exceptions or mispredicts

## Major Components

### Physical Register File (PRF)
- **File**: `TG68K_PhysicalRegFile.vhd`
- 64 physical registers (32-bit each)
- 8 read ports (4 instructions × 2 sources)
- 4 write ports (commit stage)
- Supports result forwarding from execution units

### Reorder Buffer (ROB)
- **File**: `TG68K_ReorderBuffer.vhd`
- 32 entries (configurable)
- Circular buffer with head/tail pointers
- Tracks instruction status: ISSUED → EXECUTING → COMPLETED → COMMITTED
- Handles exceptions and branch mispredictions
- Ensures in-order retirement

### Reservation Stations (RS)
- **File**: `TG68K_ReservationStation.vhd`
- 16 entries (configurable)
- Unified reservation station (all execution units)
- Stores decoded instructions with operand status
- Wake-up logic monitors broadcasts for ready operands
- Select logic chooses oldest ready instruction per EU

## Performance Characteristics

### Theoretical Peak Performance
- **IPC (Instructions Per Cycle)**: Up to 4.0
- **Fetch Bandwidth**: 4 instructions/cycle
- **Commit Bandwidth**: 4 instructions/cycle
- **Execution Bandwidth**: 4 operations/cycle (1 per EU)

### Actual Expected Performance
- **Average IPC**: 1.5 - 2.5 (depending on workload)
- **Factors affecting IPC**:
  - Instruction mix (ALU vs memory vs branches)
  - Data dependencies (RAW hazards)
  - Memory latency (cache misses)
  - Branch misprediction rate
  - Structural hazards (EU conflicts)

## Differences from Original TG68K

| Aspect | Original TG68K | SuperScalar TG68K |
|--------|----------------|-------------------|
| **Issue Width** | 1 instruction/cycle | 4 instructions/cycle |
| **Execution** | In-order, sequential | Out-of-order, parallel |
| **Pipeline** | Microcoded, variable | Fixed 8-stage pipeline |
| **Registers** | 16 architectural | 64 physical (16 architectural) |
| **ALUs** | 1 shared ALU | 4 dedicated execution units |
| **Performance** | ~0.5-1.0 IPC | ~1.5-2.5 IPC |
| **Complexity** | ~5K LUTs | ~20K LUTs (estimated) |

## Resource Usage (Estimated)

| Component | Description | Est. Size |
|-----------|-------------|-----------|
| Instruction Fetch | 4-wide fetch buffer | 500 LUTs |
| Decode Units | 4 parallel decoders | 2000 LUTs |
| Register Rename | RAT + free list | 1500 LUTs |
| Physical Register File | 64×32-bit, multi-ported | 4000 LUTs |
| Reservation Stations | 16 entries | 3000 LUTs |
| Reorder Buffer | 32 entries | 4000 LUTs |
| Execution Units | 4 units (2 ALU, 1 LSU, 1 Branch) | 4000 LUTs |
| Control Logic | Pipeline control, hazard detection | 1000 LUTs |
| **Total** | | **~20,000 LUTs** |

## Current Implementation Status

### ✅ Completed
- Package definitions and types (`TG68K_SuperScalar_Pack.vhd`)
- Instruction fetch unit (`TG68K_InstructionFetch.vhd`)
- Basic parallel decode logic (`TG68K_Decode.vhd`)
- **Complete 68K instruction decoder** (`TG68K_Complete_Decoder.vhd`) - All addressing modes
- Register renaming unit (`TG68K_RegisterRename.vhd`)
- Reorder buffer (`TG68K_ReorderBuffer.vhd`)
- Reservation stations (`TG68K_ReservationStation.vhd`)
- Execution units (`TG68K_ExecutionUnit.vhd`)
- Physical register file (`TG68K_PhysicalRegFile.vhd`)
- Top-level integration (`TG68K_SuperScalar_Core.vhd`)
- **2-level adaptive branch predictor** (`TG68K_BranchPredictor.vhd`)
- **Load/Store Queue with memory disambiguation** (`TG68K_LoadStoreQueue.vhd`)
- **Simple direct-mapped cache** (`TG68K_SimpleCache.vhd`)
- **Performance counters** (`TG68K_PerfCounters.vhd`) with IPC calculation
- **Basic testbench** (`TG68K_SuperScalar_tb.vhd`)
- **VHDL syntax fixes** - All array types properly defined

### 🔧 TODO / Future Improvements
- [ ] Integration of all new components into top-level core
- [ ] Exception handling refinement (precise exceptions)
- [ ] Multi-level cache hierarchy (L1/L2)
- [ ] TLB for virtual memory support
- [ ] Hardware prefetching
- [ ] Out-of-order load/store execution
- [ ] More sophisticated branch prediction (perceptron, TAGE)
- [ ] Comprehensive test suite with real 68K programs
- [ ] FPGA synthesis and timing optimization
- [ ] Power optimization
- [ ] Formal verification

## Usage

To use the superscalar core, instantiate `TG68K_SuperScalar_Core` instead of the original `TG68KdotC_Kernel`:

```vhdl
core: TG68K_SuperScalar_Core
   generic map(
      SR_Read => 2,
      VBR_Stackframe => 2,
      extAddr_Mode => 2,
      MUL_Mode => 2,
      DIV_Mode => 2,
      BitField => 2,
      BarrelShifter => 1,
      MUL_Hardware => 1
   )
   port map(
      clk => clk,
      nReset => nReset,
      clkena_in => clkena_in,
      -- ... (standard TG68K interface)
   );
```

## Testing and Validation

⚠️ **Warning**: This is a major architectural redesign. Extensive testing is required before use in production systems.

### Recommended Test Strategy
1. **Unit Tests**: Test each component individually
2. **Integration Tests**: Test component interactions
3. **Instruction Tests**: Run 68K instruction test suites
4. **System Tests**: Boot operating systems (AmigaOS, Atari TOS, etc.)
5. **Performance Tests**: Measure IPC and compare to original
6. **Stress Tests**: Long-running applications and edge cases

## References

- **Original TG68K**: https://github.com/TobiFlex/TG68K.C
- **68000 Architecture**: Motorola M68000 Family Programmer's Reference Manual
- **Superscalar Design**: Hennessy & Patterson, "Computer Architecture: A Quantitative Approach"
- **Out-of-Order Execution**: Modern Processor Design by Shen & Lipasti

## License

This superscalar implementation maintains the same license as the original TG68K:

GNU Lesser General Public License v3.0 or later

## Author

- **Original TG68K**: Tobias Gubener
- **SuperScalar Redesign**: 2025

---

**Note**: This is an experimental redesign. The original TG68K remains the stable, tested version for production use.
