# Critical Issues Requiring Fixes in TG68K Superscalar Core

## CRITICAL Issues (Must Fix)

### 1. **ROB Missing Old Physical Register Tracking**
**Severity**: CRITICAL
**File**: `TG68K_ROB.vhd` and `TG68K_Superscalar_Pack.vhd`

**Problem**: When instructions commit, the old physical register mapping is never freed.

**Current Code** (TG68K_ROB.vhd:161-166):
```vhdl
commit_valid(i) <= '1';
commit_data(i).valid <= '1';
commit_data(i).arch_reg <= rob(next_head).dest_arch_reg;
commit_data(i).phys_reg <= rob(next_head).dest_phys_reg;
commit_data(i).data <= rob(next_head).result;
-- commit_data(i).old_phys_reg is NEVER SET!
```

**Impact**: Physical registers are never freed after commit, causing the free list to drain and the processor to stall permanently after ~80 instructions.

**Fix Required**:
1. Add `old_phys_reg` field to `rob_entry_t` type
2. Save old physical register when instruction is allocated to ROB (from rename stage)
3. Set `commit_data(i).old_phys_reg` when committing

---

### 2. **Rename Map Not Restored on Branch Misprediction**
**Severity**: CRITICAL
**File**: `TG68K_Rename_Unit.vhd`

**Problem**: On flush (branch misprediction), the rename map is not restored to committed state.

**Current Code** (TG68K_Rename_Unit.vhd:91-96):
```vhdl
if flush = '1' then
    -- Flush pipeline - reset to committed state
    for i in 0 to ISSUE_WIDTH-1 loop
        rename_instr(i).valid <= '0';
        rename_valid(i) <= '0';
    end loop;
    -- rename_map is NOT restored!
end if;
```

**Impact**: After a branch misprediction, the rename map contains speculative mappings from the wrong path, causing incorrect register dependencies and data corruption.

**Fix Required**:
1. Maintain separate `rename_map_committed` updated only on commits
2. On flush, restore `rename_map <= rename_map_committed`
3. Also restore `free_list` to committed state

---

### 3. **Issue Logic Doesn't Check Execution Unit Type**
**Severity**: CRITICAL
**File**: `TG68K_Issue_Logic.vhd`

**Problem**: Instructions are issued to any available execution unit without checking compatibility.

**Current Code** (TG68K_Issue_Logic.vhd:180-205):
```vhdl
for exec_unit_idx in 0 to ISSUE_WIDTH-1 loop
    if exec_busy(exec_unit_idx) = '0' then
        -- Find oldest ready instruction for this unit type
        for i in 0 to RS_SIZE*ISSUE_WIDTH-1 loop
            if rs_valid(i) = '1' and ... then
                -- Issues ANY instruction to ANY unit!
                issue_valid(exec_unit_idx) <= '1';
```

**Impact**: MUL instructions sent to ALU, branches sent to divider, etc. Complete functional failure.

**Fix Required**:
Add check: `rs(i).instruction.exec_unit = unit_type(exec_unit_idx)` where unit_type maps index to type.

---

### 4. **Branch Predictor Update Uses Wrong PC**
**Severity**: HIGH
**File**: `TG68K_Superscalar_Core.vhd`

**Problem**: Branch predictor update uses result field instead of PC.

**Current Code** (TG68K_Superscalar_Core.vhd:240):
```vhdl
bp_update_pc <= complete_result(7).result when complete_valid(7) = '1' else (others => '0');
```

**Impact**: Branch predictor is trained with PC=0 for all branches, destroying prediction accuracy.

**Fix Required**:
Branch instructions need to pass their PC through the pipeline. Either:
1. Add PC field to `exec_result_t`, OR
2. Look up PC from ROB using `complete_result(7).rob_id`

---

## HIGH Priority Issues

### 5. **Free List Index Calculation Error**
**Severity**: HIGH
**File**: `TG68K_Rename_Unit.vhd`

**Problem**: Free list array indexing may be incorrect.

**Current Code** (TG68K_Rename_Unit.vhd:79-80):
```vhdl
for i in 16 to PHYS_REGS-1 loop
    free_list(i - 16) <= i;  -- Indices 0-79 hold values 16-95
end loop;
```

But then:
```vhdl
free_ptr := free_list_head;  -- free_list_head starts at 16
new_phys_reg := free_list(free_ptr);  -- Accesses free_list(16)!
```

**Impact**: Out-of-bounds array access when `free_ptr >= 80`. Will fail in simulation.

**Fix Required**:
Use `free_list(free_ptr mod (PHYS_REGS - ARCH_REGS))` or rework free list management.

---

### 6. **ROB Doesn't Track Instruction PC for Branch Update**
**Severity**: HIGH
**File**: `TG68K_ROB.vhd`

**Problem**: ROB stores PC but doesn't provide it back for branch predictor updates.

**Current**: PC is stored in ROB but not accessible when instruction completes.

**Impact**: Can't update branch predictor with correct PC (see issue #4).

**Fix Required**:
Add PC to `exec_result_t` or provide mechanism to retrieve PC from ROB.

---

### 7. **Missing Flush Handling in Issue Logic**
**Severity**: MEDIUM
**File**: `TG68K_Issue_Logic.vhd`

**Problem**: Reservation stations are flushed on misprediction, but may contain instructions from wrong path.

**Current Code**: RS entries are only cleared when issued, not on flush.

**Impact**: Instructions from mispredicted path may execute and corrupt architectural state.

**Fix Required**:
Add flush handling to clear all RS entries when `flush = '1'`.

---

## MEDIUM Priority Issues

### 8. **Decode Stage Doesn't Set All Instruction Fields**
**Severity**: MEDIUM
**File**: `TG68K_Decode_Unit.vhd`

**Problem**: Decoded instructions don't set `branch_target`, `branch_predicted`, ROB ID, physical registers.

**Impact**: Later stages have incomplete information. Branch target needs to be computed in decode.

**Fix Required**:
Add branch target calculation in decode for PC-relative branches.

---

### 9. **Physical Register File Initialization**
**Severity**: MEDIUM
**File**: `TG68K_Superscalar_Core.vhd`

**Problem**: Physical register file initialized to all-ready state.

**Current Code** (TG68K_Superscalar_Core.vhd:369-376):
```vhdl
for i in 0 to PHYS_REGS-1 loop
    phys_reg_file(i).ready <= '1';  -- All registers ready!
end loop;
```

**Impact**: Incorrect initial state. Only architectural registers (0-15) should be ready initially.

**Fix Required**:
Set `ready <= '1'` for i < 16, `ready <= '0'` for i >= 16.

---

### 10. **Division Result Not Stored in Variables**
**Severity**: LOW
**File**: `TG68K_Exec_Units.vhd`

**Problem**: Division computes quotient/remainder but result is only sent after 32 cycles.

**Current Code**: Variables quotient/remainder computed but not preserved during iteration.

**Impact**: Division result is lost during multi-cycle operation.

**Fix Required**:
Use signals instead of variables for quotient/remainder, or store in div_result immediately.

---

## Summary Table

| # | Issue | Severity | Impact |
|---|-------|----------|--------|
| 1 | ROB old_phys_reg not tracked | CRITICAL | Processor stalls after 80 instructions |
| 2 | Rename map not restored on flush | CRITICAL | Data corruption after misprediction |
| 3 | Issue logic ignores exec unit type | CRITICAL | Complete functional failure |
| 4 | Branch predictor update wrong PC | HIGH | Branch prediction useless |
| 5 | Free list indexing error | HIGH | Array bounds violation |
| 6 | ROB doesn't provide PC for branches | HIGH | Can't fix issue #4 |
| 7 | RS not flushed on misprediction | MEDIUM | Wrong-path instructions execute |
| 8 | Decode doesn't compute branch target | MEDIUM | Branches won't work |
| 9 | Phys reg file init wrong | MEDIUM | Incorrect initial state |
| 10 | Division result not preserved | LOW | Division returns garbage |

---

## Fix Priority

**Must fix before ANY testing:**
1. Issue #3 (exec unit type check)
2. Issue #1 (old_phys_reg tracking)
3. Issue #2 (rename map restore)

**Must fix before branch testing:**
4. Issue #4 + #6 (branch PC tracking)
5. Issue #8 (branch target calculation)

**Should fix for correctness:**
6. Issue #5 (free list indexing)
7. Issue #7 (RS flush)
8. Issue #9 (phys reg init)

**Can defer:**
9. Issue #10 (division) - already marked as needing proper algorithm
