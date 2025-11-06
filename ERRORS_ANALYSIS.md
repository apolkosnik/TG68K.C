# Error Analysis for TG68K Superscalar Core

## Critical Errors

### 1. **Branch Condition Code Evaluation - CRITICAL**
**File**: `TG68K_Exec_Units.vhd`, lines 310-325

**Problem**: Branch condition evaluation uses incorrect flag bit positions for some conditions.

The 68K condition code register (CCR) has flags at:
- Bit 0: C (Carry)
- Bit 1: V (Overflow)
- Bit 2: Z (Zero)
- Bit 3: N (Negative)
- Bit 4: X (Extend)

**Current (INCORRECT)**:
```vhdl
when "0010" => condition_met := not flags(0);       -- BHI (!C && !Z) - WRONG!
when "0011" => condition_met := flags(0);           -- BLS (C || Z)   - WRONG!
```

**Should be**:
```vhdl
when "0010" => condition_met := (not flags(0)) and (not flags(2));  -- BHI (!C && !Z)
when "0011" => condition_met := flags(0) or flags(2);               -- BLS (C || Z)
```

**Impact**: Branch instructions will behave incorrectly, causing program logic errors.

---

### 2. **Division Operator Non-Synthesizable - MEDIUM**
**File**: `TG68K_Exec_Units.vhd`, lines 275-276

**Problem**: Uses VHDL `/` and `mod` operators which may not synthesize in all FPGA tools.

```vhdl
quotient := dividend(31 downto 0) / divisor;
remainder := dividend(31 downto 0) mod divisor;
```

**Impact**: May fail synthesis on some FPGA toolchains. Already noted in comments as placeholder.

**Solution**: Need to implement proper restoring or non-restoring division algorithm.

---

### 3. **Missing Field Initializations in Execution Units - MEDIUM**
**File**: `TG68K_Exec_Units.vhd`, multiple locations

**Problem**: Some execution units don't initialize all `exec_result_t` record fields.

For example, the divider (lines 237-289) doesn't initialize:
- `flags` field (never set)
- `branch_taken`, `branch_target`, `branch_mispred` (only set `is_branch`)

**Impact**: Undefined values could propagate through pipeline, causing unpredictable behavior.

**Solution**: Initialize all fields even if not used:
```vhdl
div_result.flags <= (others => '0');
div_result.branch_taken <= '0';
div_result.branch_target <= (others => '0');
div_result.branch_mispred <= '0';
```

---

### 4. **ALU Flag Generation Incomplete - MEDIUM**
**File**: `TG68K_Exec_Units.vhd`, lines 87-184

**Problem**: ALU operations only set Z and N flags, but C (carry) and V (overflow) are not computed.

```vhdl
flags := (others => '0');  -- Initializes all flags to 0
-- Only sets flags(2) for Z and flags(3) for N
-- Never sets flags(0) for C or flags(1) for V
```

**Impact**: Condition codes for carry and overflow will always be 0, breaking programs that rely on these flags (e.g., multi-precision arithmetic).

**Solution**: Add carry and overflow detection logic for ADD/SUB operations.

---

### 5. **Multiplier Missing Destination Register - LOW**
**File**: `TG68K_Exec_Units.vhd`, lines 197-230

**Problem**: Multiplier sets result but never initializes some record fields.

Missing initializations:
- `dest_phys_reg` (set but not in else clause)
- `branch_taken`, `branch_target`, `branch_mispred`

**Impact**: Minor - may cause simulation warnings but likely won't affect synthesis.

---

### 6. **Register Index Out of Bounds Risk - LOW**
**File**: `TG68K_Decode_Unit.vhd`, line 98

**Problem**: Adds constant offset to register index without bounds checking.

```vhdl
instr.dest_arch_reg := to_integer(unsigned(opcode(11 downto 9))) + 8; -- Data reg
```

If `opcode(11 downto 9)` is 7, result is 15 (A7), which is valid.
But comment says "Data reg" which should be 0-7, not 8-15.

**Impact**: LOW - Likely a comment error. Address registers are 8-15.

---

## Warnings (Non-Critical)

### 7. **Combinatorial Process Sensitivity List**
**File**: `TG68K_Exec_Units.vhd`, lines 399-433

**Status**: CORRECT - Process has complete sensitivity list. Not an error.

---

### 8. **ROB Circular Queue Logic**
**File**: `TG68K_ROB.vhd`

**Status**: CORRECT - Uses modulo arithmetic correctly for circular buffer.

---

### 9. **Free List Management**
**File**: `TG68K_Rename_Unit.vhd`

**Potential Issue**: Free list management increments count when freeing and decrements when allocating, but complex logic may have off-by-one errors under heavy load.

**Recommendation**: Add assertions or boundary checks in simulation.

---

## Summary

### Critical (Must Fix):
1. ✗ Branch condition evaluation incorrect
2. ✗ ALU carry/overflow flags not computed
3. ✗ Missing exec_result_t field initializations

### Medium (Should Fix):
4. ✗ Division uses non-synthesizable operators (already noted as TODO)
5. ✗ Some record fields not initialized

### Low Priority:
6. ⚠ Comment/register mapping clarification needed

### Total Lines of Code: 3,851 lines (new superscalar files)

---

## Recommended Fixes Priority

1. **FIRST**: Fix branch condition code evaluation (lines 310-325 in TG68K_Exec_Units.vhd)
2. **SECOND**: Add carry/overflow flag computation in ALU
3. **THIRD**: Initialize all exec_result_t fields in all execution units
4. **FOURTH**: Replace division operators with proper algorithm
5. **LAST**: Add simulation assertions for bounds checking

---

## Testing Recommendations

1. **Unit test branch conditions** with all 16 68K condition codes
2. **Test multi-precision arithmetic** (relies on carry flag)
3. **Verify division by zero exception** handling
4. **Stress test register renaming** with deep instruction windows
5. **Run 68K compliance tests** to catch ISA-level errors
