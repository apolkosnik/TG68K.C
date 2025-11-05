--------------------------------------------------------------------------------
-- TG68K Superscalar Package
-- Defines types and constants for 8-issue superscalar architecture
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package TG68K_Superscalar_Pack is

    -- Pipeline Configuration
    constant ISSUE_WIDTH        : integer := 8;    -- 8-issue superscalar
    constant ROB_SIZE           : integer := 128;  -- Reorder buffer entries
    constant PHYS_REGS          : integer := 96;   -- Physical registers
    constant ARCH_REGS          : integer := 16;   -- Architectural registers (D0-D7, A0-A7)
    constant RS_SIZE            : integer := 16;   -- Reservation station entries per unit
    constant NUM_ALU            : integer := 4;    -- ALU execution units
    constant NUM_MUL            : integer := 1;    -- Multiplier units
    constant NUM_DIV            : integer := 1;    -- Divider units
    constant NUM_LDST           : integer := 1;    -- Load/Store units
    constant NUM_BRANCH         : integer := 1;    -- Branch units
    constant BTB_SIZE           : integer := 512;  -- Branch target buffer entries
    constant BHT_SIZE           : integer := 2048; -- Branch history table entries

    -- Execution Unit Types
    type exec_unit_type is (
        EXEC_ALU,           -- Integer ALU (ADD, SUB, AND, OR, XOR, etc.)
        EXEC_MUL,           -- Multiplier
        EXEC_DIV,           -- Divider
        EXEC_SHIFT,         -- Barrel shifter
        EXEC_LDST,          -- Load/Store
        EXEC_BRANCH,        -- Branch/Jump
        EXEC_NONE           -- No execution unit
    );

    -- Operation Types (expanded from original 89 operations)
    type operation_type is (
        OP_NOP,
        OP_MOVE, OP_MOVEQ, OP_MOVEA,
        OP_ADD, OP_ADDI, OP_ADDQ, OP_ADDA, OP_ADDX,
        OP_SUB, OP_SUBI, OP_SUBQ, OP_SUBA, OP_SUBX,
        OP_AND, OP_ANDI, OP_OR, OP_ORI, OP_EOR, OP_EORI, OP_NOT,
        OP_MULU, OP_MULS, OP_DIVU, OP_DIVS,
        OP_ASL, OP_ASR, OP_LSL, OP_LSR, OP_ROL, OP_ROR, OP_ROXL, OP_ROXR,
        OP_BTST, OP_BSET, OP_BCHG, OP_BCLR,
        OP_CMP, OP_CMPI, OP_CMPM, OP_CMPA,
        OP_TST, OP_CLR, OP_NEG, OP_NEGX, OP_EXT, OP_SWAP,
        OP_BRA, OP_BSR, OP_BCC, OP_DBCC,
        OP_JMP, OP_JSR, OP_RTS, OP_RTR, OP_RTE,
        OP_LEA, OP_PEA, OP_LINK, OP_UNLK,
        OP_MOVEM, OP_MOVEP, OP_MOVESR, OP_MOVEUSP,
        OP_TRAP, OP_TRAPV, OP_CHK,
        OP_ABCD, OP_SBCD, OP_NBCD,
        OP_BFTST, OP_BFEXTU, OP_BFEXTS, OP_BFCHG, OP_BFCLR, OP_BFSET, OP_BFINS, OP_BFFFO,
        OP_INVALID
    );

    -- Instruction Format (after decode)
    type instruction_t is record
        valid           : std_logic;                        -- Valid instruction
        pc              : std_logic_vector(31 downto 0);    -- Program counter
        opcode          : std_logic_vector(15 downto 0);    -- Raw opcode
        operation       : operation_type;                   -- Decoded operation
        exec_unit       : exec_unit_type;                   -- Execution unit required

        -- Source operands
        src1_valid      : std_logic;                        -- Source 1 valid
        src1_arch_reg   : integer range 0 to ARCH_REGS-1;   -- Architectural register
        src1_phys_reg   : integer range 0 to PHYS_REGS-1;   -- Physical register (after rename)
        src1_ready      : std_logic;                        -- Operand ready

        src2_valid      : std_logic;
        src2_arch_reg   : integer range 0 to ARCH_REGS-1;
        src2_phys_reg   : integer range 0 to PHYS_REGS-1;
        src2_ready      : std_logic;

        -- Destination operand
        dest_valid      : std_logic;
        dest_arch_reg   : integer range 0 to ARCH_REGS-1;
        dest_phys_reg   : integer range 0 to PHYS_REGS-1;

        -- Immediate/displacement
        immediate       : std_logic_vector(31 downto 0);
        imm_valid       : std_logic;

        -- Memory access
        mem_read        : std_logic;
        mem_write       : std_logic;
        mem_size        : std_logic_vector(1 downto 0);     -- 00=byte, 01=word, 10=long

        -- Branch info
        is_branch       : std_logic;
        branch_cond     : std_logic_vector(3 downto 0);     -- Branch condition
        branch_target   : std_logic_vector(31 downto 0);
        branch_predicted: std_logic;                        -- Predicted taken/not-taken

        -- Exception handling
        may_trap        : std_logic;                        -- May cause exception
        privilege       : std_logic;                        -- Requires supervisor mode

        -- ROB entry
        rob_id          : integer range 0 to ROB_SIZE-1;
    end record;

    -- Array of instructions (for pipeline stages)
    type instruction_array_t is array (0 to ISSUE_WIDTH-1) of instruction_t;

    -- Reorder Buffer Entry
    type rob_entry_t is record
        valid           : std_logic;
        complete        : std_logic;                        -- Execution complete
        pc              : std_logic_vector(31 downto 0);
        operation       : operation_type;

        dest_valid      : std_logic;
        dest_arch_reg   : integer range 0 to ARCH_REGS-1;
        dest_phys_reg   : integer range 0 to PHYS_REGS-1;
        result          : std_logic_vector(31 downto 0);

        is_branch       : std_logic;
        branch_taken    : std_logic;
        branch_mispred  : std_logic;
        branch_target   : std_logic_vector(31 downto 0);

        exception       : std_logic;
        exception_vec   : std_logic_vector(7 downto 0);
    end record;

    type rob_array_t is array (0 to ROB_SIZE-1) of rob_entry_t;

    -- Physical Register File Entry
    type phys_reg_t is record
        valid           : std_logic;
        data            : std_logic_vector(31 downto 0);
        ready           : std_logic;                        -- Data available
    end record;

    type phys_reg_file_t is array (0 to PHYS_REGS-1) of phys_reg_t;

    -- Register Rename Map (Architectural -> Physical)
    type rename_map_t is array (0 to ARCH_REGS-1) of integer range 0 to PHYS_REGS-1;

    -- Free List for physical registers
    type free_list_t is array (0 to PHYS_REGS-1) of integer range 0 to PHYS_REGS-1;

    -- Reservation Station Entry
    type rs_entry_t is record
        valid           : std_logic;
        instruction     : instruction_t;

        -- Operand values (from reg file or forwarding)
        src1_value      : std_logic_vector(31 downto 0);
        src2_value      : std_logic_vector(31 downto 0);

        -- Issue tracking
        issued          : std_logic;
        age             : integer range 0 to ROB_SIZE-1;    -- For oldest-first issue
    end record;

    type rs_array_t is array (0 to RS_SIZE-1) of rs_entry_t;

    -- Execution Result (from execution units to ROB/forwarding)
    type exec_result_t is record
        valid           : std_logic;
        rob_id          : integer range 0 to ROB_SIZE-1;
        dest_phys_reg   : integer range 0 to PHYS_REGS-1;
        result          : std_logic_vector(31 downto 0);
        flags           : std_logic_vector(7 downto 0);     -- Condition codes

        -- Branch resolution
        is_branch       : std_logic;
        branch_taken    : std_logic;
        branch_target   : std_logic_vector(31 downto 0);
        branch_mispred  : std_logic;

        -- Exception
        exception       : std_logic;
        exception_vec   : std_logic_vector(7 downto 0);
    end record;

    type exec_result_array_t is array (0 to ISSUE_WIDTH-1) of exec_result_t;

    -- Branch Predictor - Branch Target Buffer Entry
    type btb_entry_t is record
        valid           : std_logic;
        tag             : std_logic_vector(19 downto 0);    -- PC tag
        target          : std_logic_vector(31 downto 0);    -- Branch target
        prediction      : std_logic_vector(1 downto 0);     -- 2-bit saturating counter
    end record;

    type btb_array_t is array (0 to BTB_SIZE-1) of btb_entry_t;

    -- Branch History Table Entry (2-bit saturating counter)
    type bht_entry_t is record
        prediction      : std_logic_vector(1 downto 0);     -- 00=strongly NT, 11=strongly T
    end record;

    type bht_array_t is array (0 to BHT_SIZE-1) of bht_entry_t;

    -- Commit Queue Entry
    type commit_entry_t is record
        valid           : std_logic;
        arch_reg        : integer range 0 to ARCH_REGS-1;
        phys_reg        : integer range 0 to PHYS_REGS-1;
        old_phys_reg    : integer range 0 to PHYS_REGS-1;   -- For freeing
        data            : std_logic_vector(31 downto 0);
    end record;

    type commit_array_t is array (0 to ISSUE_WIDTH-1) of commit_entry_t;

    -- Helper function: Calculate ROB index with wraparound
    function rob_next(idx : integer; offset : integer) return integer;

    -- Helper function: Check if ROB is full
    function rob_full(head : integer; tail : integer; size : integer) return boolean;

    -- Helper function: Check if ROB is empty
    function rob_empty(head : integer; tail : integer) return boolean;

    -- Helper function: Get number of free ROB entries
    function rob_free_entries(head : integer; tail : integer; size : integer) return integer;

end package TG68K_Superscalar_Pack;

package body TG68K_Superscalar_Pack is

    function rob_next(idx : integer; offset : integer) return integer is
    begin
        return (idx + offset) mod ROB_SIZE;
    end function;

    function rob_full(head : integer; tail : integer; size : integer) return boolean is
    begin
        return ((tail + 1) mod size) = head;
    end function;

    function rob_empty(head : integer; tail : integer) return boolean is
    begin
        return head = tail;
    end function;

    function rob_free_entries(head : integer; tail : integer; size : integer) return integer is
        variable entries : integer;
    begin
        if tail >= head then
            entries := size - (tail - head) - 1;
        else
            entries := head - tail - 1;
        end if;
        return entries;
    end function;

end package body TG68K_Superscalar_Pack;
