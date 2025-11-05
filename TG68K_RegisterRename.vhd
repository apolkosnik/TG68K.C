------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K SuperScalar Register Renaming Unit                                --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Implements register renaming for out-of-order execution                 --
-- Maps architectural registers (16) to physical registers (64)            --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_RegisterRename is
    port(
        clk             : in std_logic;
        reset           : in std_logic;
        enable          : in std_logic;

        -- Input: Decoded instructions
        decoded_valid   : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        decoded_inst    : in decoded_inst_array_t;

        -- Output: Physical register mappings
        src1_preg       : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
        src2_preg       : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
        dest_preg       : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
        old_dest_preg   : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);

        -- Free list management
        alloc_success   : out std_logic;  -- All registers allocated successfully

        -- Commit interface (frees old physical registers)
        commit_valid    : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        commit_preg     : in array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);

        -- Flush on branch misprediction
        flush           : in std_logic;
        checkpoint_restore : in std_logic
    );
end TG68K_RegisterRename;

architecture rtl of TG68K_RegisterRename is

    -- Register Allocation Table (RAT) - maps arch regs to physical regs
    signal rat          : rename_table_t;
    signal rat_next     : rename_table_t;

    -- Free list of physical registers
    signal free_list    : std_logic_vector(PHYS_REG_COUNT-1 downto 0);
    signal free_count   : integer range 0 to PHYS_REG_COUNT;

    -- Checkpoint for branch misprediction recovery
    signal rat_checkpoint : rename_table_t;

    -- Internal signals
    type preg_array is array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
    signal alloc_pregs  : preg_array;
    signal can_allocate : std_logic;

begin

    -- Combinational logic for register renaming
    process(decoded_valid, decoded_inst, rat, free_list)
        variable temp_rat : rename_table_t;
        variable temp_free_list : std_logic_vector(PHYS_REG_COUNT-1 downto 0);
        variable free_idx : integer;
        variable allocated : integer;
    begin
        temp_rat := rat;
        temp_free_list := free_list;
        allocated := 0;
        can_allocate <= '1';

        -- Process each instruction for renaming
        for i in 0 to ISSUE_WIDTH-1 loop
            if decoded_valid(i) = '1' then

                -- Map source registers
                if decoded_inst(i).uses_src1 = '1' then
                    src1_preg(i) <= temp_rat(to_integer(unsigned(decoded_inst(i).src_reg1)));
                else
                    src1_preg(i) <= (others => '0');
                end if;

                if decoded_inst(i).uses_src2 = '1' then
                    src2_preg(i) <= temp_rat(to_integer(unsigned(decoded_inst(i).src_reg2)));
                else
                    src2_preg(i) <= (others => '0');
                end if;

                -- Allocate destination register
                if decoded_inst(i).writes_dest = '1' then
                    -- Find next free physical register
                    free_idx := -1;
                    for j in 0 to PHYS_REG_COUNT-1 loop
                        if temp_free_list(j) = '1' and free_idx = -1 then
                            free_idx := j;
                            temp_free_list(j) := '0';  -- Allocate this register
                        end if;
                    end loop;

                    if free_idx /= -1 then
                        -- Save old mapping for commit/recovery
                        old_dest_preg(i) <= temp_rat(to_integer(unsigned(decoded_inst(i).dest_reg)));

                        -- Update RAT with new physical register
                        dest_preg(i) <= std_logic_vector(to_unsigned(free_idx, 6));
                        temp_rat(to_integer(unsigned(decoded_inst(i).dest_reg))) := std_logic_vector(to_unsigned(free_idx, 6));
                        alloc_pregs(i) <= std_logic_vector(to_unsigned(free_idx, 6));
                        allocated := allocated + 1;
                    else
                        -- No free registers - stall
                        can_allocate <= '0';
                        dest_preg(i) <= (others => '0');
                        old_dest_preg(i) <= (others => '0');
                    end if;
                else
                    dest_preg(i) <= (others => '0');
                    old_dest_preg(i) <= (others => '0');
                end if;

            else
                src1_preg(i) <= (others => '0');
                src2_preg(i) <= (others => '0');
                dest_preg(i) <= (others => '0');
                old_dest_preg(i) <= (others => '0');
            end if;
        end loop;

        rat_next <= temp_rat;
        alloc_success <= can_allocate;
    end process;

    -- Sequential logic for RAT and free list updates
    process(clk, reset)
    begin
        if reset = '1' then
            -- Initialize RAT: arch reg i maps to physical reg i
            for i in 0 to ARCH_REG_COUNT-1 loop
                rat(i) <= std_logic_vector(to_unsigned(i, 6));
            end loop;

            -- Initialize free list: registers 16-63 are free
            free_list <= (others => '0');
            for i in ARCH_REG_COUNT to PHYS_REG_COUNT-1 loop
                free_list(i) <= '1';
            end loop;

            free_count <= PHYS_REG_COUNT - ARCH_REG_COUNT;
            rat_checkpoint <= (others => (others => '0'));

        elsif rising_edge(clk) then

            -- Handle flush/checkpoint restore
            if flush = '1' and checkpoint_restore = '1' then
                rat <= rat_checkpoint;
                -- Note: Free list recovery requires more complex logic
                -- For simplicity, we reset it here

            elsif enable = '1' then

                -- Update RAT if allocation succeeded
                if can_allocate = '1' then
                    rat <= rat_next;
                end if;

                -- Free committed physical registers
                for i in 0 to ISSUE_WIDTH-1 loop
                    if commit_valid(i) = '1' then
                        free_list(to_integer(unsigned(commit_preg(i)))) <= '1';
                    end if;
                end loop;

                -- Update free count
                -- (simplified - actual implementation would track precisely)

            end if;

            -- Create checkpoint for recovery (simplified - only one checkpoint)
            if enable = '1' and decoded_valid /= "0000" then
                -- Save checkpoint when dispatching branches
                for i in 0 to ISSUE_WIDTH-1 loop
                    if decoded_valid(i) = '1' and decoded_inst(i).is_branch = '1' then
                        rat_checkpoint <= rat;
                    end if;
                end loop;
            end if;

        end if;
    end process;

end rtl;
