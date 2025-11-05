------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K SuperScalar 4-Issue Package                                       --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify--
-- it under the terms of the GNU Lesser General Public License as published--
-- by the Free Software Foundation, either version 3 of the License, or    --
-- (at your option) any later version.                                     --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;

package TG68K_SuperScalar_Pack is

    -- Superscalar configuration constants
    constant ISSUE_WIDTH        : integer := 4;   -- 4-issue superscalar
    constant ROB_SIZE          : integer := 32;  -- Reorder buffer entries
    constant RS_SIZE           : integer := 16;  -- Reservation station entries
    constant PHYS_REG_COUNT    : integer := 64;  -- Physical register file size (for renaming)
    constant ARCH_REG_COUNT    : integer := 16;  -- Architectural registers (D0-D7, A0-A7)

    -- Execution unit types
    constant EU_ALU0           : integer := 0;   -- ALU Unit 0 (general arithmetic)
    constant EU_ALU1           : integer := 1;   -- ALU Unit 1 (general arithmetic)
    constant EU_LSU            : integer := 2;   -- Load/Store Unit
    constant EU_BRANCH         : integer := 3;   -- Branch/Control Unit
    constant EU_COUNT          : integer := 4;   -- Total execution units

    -- Instruction dispatch status
    type dispatch_status_t is (
        DISP_READY,         -- Ready to dispatch
        DISP_STALL,         -- Stalled (resource conflict)
        DISP_RAW_HAZARD,    -- Read-After-Write dependency
        DISP_WAW_HAZARD,    -- Write-After-Write dependency
        DISP_STRUCTURAL     -- Structural hazard (no free EU)
    );

    -- ROB entry status
    type rob_status_t is (
        ROB_INVALID,        -- Entry is free
        ROB_ISSUED,         -- Issued to execution unit
        ROB_EXECUTING,      -- Currently executing
        ROB_COMPLETED,      -- Execution completed, waiting to commit
        ROB_COMMITTED       -- Committed (will be freed)
    );

    -- Decoded instruction information
    type decoded_inst_t is record
        valid           : std_logic;                        -- Valid instruction
        pc              : std_logic_vector(31 downto 0);    -- Program counter
        opcode          : std_logic_vector(15 downto 0);    -- Opcode
        inst_type       : std_logic_vector(3 downto 0);     -- Instruction type
        eu_type         : integer range 0 to EU_COUNT-1;    -- Target execution unit
        src_reg1        : std_logic_vector(3 downto 0);     -- Source register 1
        src_reg2        : std_logic_vector(3 downto 0);     -- Source register 2
        dest_reg        : std_logic_vector(3 downto 0);     -- Destination register
        uses_src1       : std_logic;                        -- Uses source 1?
        uses_src2       : std_logic;                        -- Uses source 2?
        writes_dest     : std_logic;                        -- Writes destination?
        is_branch       : std_logic;                        -- Is branch instruction?
        is_load         : std_logic;                        -- Is load instruction?
        is_store        : std_logic;                        -- Is store instruction?
        immediate       : std_logic_vector(31 downto 0);    -- Immediate value
        displacement    : std_logic_vector(31 downto 0);    -- Address displacement
    end record;

    type decoded_inst_array_t is array (0 to ISSUE_WIDTH-1) of decoded_inst_t;

    -- ROB entry
    type rob_entry_t is record
        valid           : std_logic;                        -- Entry is valid
        status          : rob_status_t;                     -- Entry status
        pc              : std_logic_vector(31 downto 0);    -- PC of instruction
        dest_reg        : std_logic_vector(3 downto 0);     -- Destination register (arch)
        dest_preg       : std_logic_vector(5 downto 0);     -- Destination register (physical)
        old_preg        : std_logic_vector(5 downto 0);     -- Previous physical register
        result          : std_logic_vector(31 downto 0);    -- Result value
        eu_type         : integer range 0 to EU_COUNT-1;    -- Execution unit type
        is_branch       : std_logic;                        -- Is branch?
        branch_taken    : std_logic;                        -- Was branch taken?
        branch_target   : std_logic_vector(31 downto 0);    -- Branch target address
        exception       : std_logic;                        -- Exception occurred?
        exception_vec   : std_logic_vector(7 downto 0);     -- Exception vector
    end record;

    type rob_array_t is array (0 to ROB_SIZE-1) of rob_entry_t;

    -- Reservation Station entry
    type rs_entry_t is record
        valid           : std_logic;                        -- Entry is valid
        opcode          : std_logic_vector(15 downto 0);    -- Opcode
        pc              : std_logic_vector(31 downto 0);    -- PC
        rob_index       : integer range 0 to ROB_SIZE-1;    -- ROB entry index
        eu_type         : integer range 0 to EU_COUNT-1;    -- Target execution unit

        -- Source operand 1
        src1_ready      : std_logic;                        -- Operand 1 ready?
        src1_value      : std_logic_vector(31 downto 0);    -- Operand 1 value
        src1_preg       : std_logic_vector(5 downto 0);     -- Source physical register

        -- Source operand 2
        src2_ready      : std_logic;                        -- Operand 2 ready?
        src2_value      : std_logic_vector(31 downto 0);    -- Operand 2 value
        src2_preg       : std_logic_vector(5 downto 0);     -- Source physical register

        dest_preg       : std_logic_vector(5 downto 0);     -- Destination physical register
        immediate       : std_logic_vector(31 downto 0);    -- Immediate value
        is_branch       : std_logic;                        -- Is branch?
        is_load         : std_logic;                        -- Is load?
        is_store        : std_logic;                        -- Is store?
    end record;

    type rs_array_t is array (0 to RS_SIZE-1) of rs_entry_t;

    -- Register Renaming Table (maps architectural to physical registers)
    type rename_table_t is array (0 to ARCH_REG_COUNT-1) of std_logic_vector(5 downto 0);

    -- Physical Register File
    type phys_regfile_t is array (0 to PHYS_REG_COUNT-1) of std_logic_vector(31 downto 0);

    -- Free list for physical registers
    type free_list_t is array (0 to PHYS_REG_COUNT-1) of std_logic;

    -- Execution unit status
    type eu_status_t is record
        busy            : std_logic;                        -- Unit is busy
        rob_index       : integer range 0 to ROB_SIZE-1;    -- ROB entry being executed
        cycles_left     : integer range 0 to 63;            -- Cycles remaining
    end record;

    type eu_status_array_t is array (0 to EU_COUNT-1) of eu_status_t;

    -- Instruction fetch buffer (holds 4 fetched instructions)
    type fetch_buffer_t is array (0 to ISSUE_WIDTH-1) of std_logic_vector(15 downto 0);

    -- Common reset values
    constant DECODED_INST_INIT : decoded_inst_t := (
        valid => '0',
        pc => (others => '0'),
        opcode => (others => '0'),
        inst_type => (others => '0'),
        eu_type => 0,
        src_reg1 => (others => '0'),
        src_reg2 => (others => '0'),
        dest_reg => (others => '0'),
        uses_src1 => '0',
        uses_src2 => '0',
        writes_dest => '0',
        is_branch => '0',
        is_load => '0',
        is_store => '0',
        immediate => (others => '0'),
        displacement => (others => '0')
    );

    constant ROB_ENTRY_INIT : rob_entry_t := (
        valid => '0',
        status => ROB_INVALID,
        pc => (others => '0'),
        dest_reg => (others => '0'),
        dest_preg => (others => '0'),
        old_preg => (others => '0'),
        result => (others => '0'),
        eu_type => 0,
        is_branch => '0',
        branch_taken => '0',
        branch_target => (others => '0'),
        exception => '0',
        exception_vec => (others => '0')
    );

    constant RS_ENTRY_INIT : rs_entry_t := (
        valid => '0',
        opcode => (others => '0'),
        pc => (others => '0'),
        rob_index => 0,
        eu_type => 0,
        src1_ready => '0',
        src1_value => (others => '0'),
        src1_preg => (others => '0'),
        src2_ready => '0',
        src2_value => (others => '0'),
        src2_preg => (others => '0'),
        dest_preg => (others => '0'),
        immediate => (others => '0'),
        is_branch => '0',
        is_load => '0',
        is_store => '0'
    );

    constant EU_STATUS_INIT : eu_status_t := (
        busy => '0',
        rob_index => 0,
        cycles_left => 0
    );

end package;
