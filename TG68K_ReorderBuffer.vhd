------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K SuperScalar Reorder Buffer (ROB)                                  --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Tracks in-flight instructions and ensures in-order commit               --
-- Size: 32 entries (configurable via ROB_SIZE)                            --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_ReorderBuffer is
    port(
        clk             : in std_logic;
        reset           : in std_logic;
        enable          : in std_logic;

        -- Dispatch interface (allocate ROB entries)
        dispatch_valid  : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        dispatch_inst   : in decoded_inst_array_t;
        dispatch_dest_preg : in preg_array_t;
        dispatch_old_preg  : in preg_array_t;

        rob_full        : out std_logic;
        rob_tail        : out integer range 0 to ROB_SIZE-1;
        alloc_rob_index : out rob_idx_array_t;

        -- Completion interface (execution units write results)
        complete_valid  : in std_logic_vector(EU_COUNT-1 downto 0);
        complete_rob_idx: in eu_rob_idx_array_t;
        complete_result : in eu_data_array_t;
        complete_exception : in std_logic_vector(EU_COUNT-1 downto 0);
        complete_dest_preg : out eu_preg_array_t;  -- Dest preg for broadcast

        -- Commit interface (retire instructions in order)
        commit_valid    : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
        commit_dest_reg : out reg_array_t;
        commit_dest_preg: out preg_array_t;
        commit_old_preg : out preg_array_t;
        commit_result   : out data_array_t;
        commit_pc       : out pc_array_t;

        -- Branch misprediction
        branch_mispredict : out std_logic;
        branch_target     : out std_logic_vector(31 downto 0);
        flush_pipeline    : out std_logic;

        -- Exception handling
        exception_valid   : out std_logic;
        exception_pc      : out std_logic_vector(31 downto 0);
        exception_vector  : out std_logic_vector(7 downto 0)
    );
end TG68K_ReorderBuffer;

architecture rtl of TG68K_ReorderBuffer is

    signal rob          : rob_array_t;
    signal head_ptr     : integer range 0 to ROB_SIZE-1;
    signal tail_ptr     : integer range 0 to ROB_SIZE-1;
    signal entry_count  : integer range 0 to ROB_SIZE;
    signal is_full      : std_logic;

begin

    rob_full <= is_full;
    rob_tail <= tail_ptr;

    -- Check if ROB is full
    process(entry_count)
    begin
        if entry_count >= (ROB_SIZE - ISSUE_WIDTH) then
            is_full <= '1';
        else
            is_full <= '0';
        end if;
    end process;

    -- Provide dest_preg for completing instructions (for broadcast)
    process(complete_valid, complete_rob_idx, rob)
    begin
        for i in 0 to EU_COUNT-1 loop
            if complete_valid(i) = '1' then
                complete_dest_preg(i) <= rob(complete_rob_idx(i)).dest_preg;
            else
                complete_dest_preg(i) <= (others => '0');
            end if;
        end loop;
    end process;

    -- Main ROB control logic
    process(clk, reset)
        variable dispatch_count : integer;
        variable commit_count : integer;
        variable new_tail : integer;
        variable new_head : integer;
    begin
        if reset = '1' then
            rob <= (others => ROB_ENTRY_INIT);
            head_ptr <= 0;
            tail_ptr <= 0;
            entry_count <= 0;

            commit_valid <= (others => '0');
            branch_mispredict <= '0';
            flush_pipeline <= '0';
            exception_valid <= '0';

        elsif rising_edge(clk) then

            if enable = '1' then

                -- Default outputs
                commit_valid <= (others => '0');
                branch_mispredict <= '0';
                flush_pipeline <= '0';
                exception_valid <= '0';

                -- =====================================================
                -- DISPATCH: Allocate ROB entries for new instructions
                -- =====================================================
                dispatch_count := 0;
                new_tail := tail_ptr;

                for i in 0 to ISSUE_WIDTH-1 loop
                    if dispatch_valid(i) = '1' and is_full = '0' then
                        -- Allocate ROB entry
                        rob(new_tail).valid <= '1';
                        rob(new_tail).status <= ROB_ISSUED;
                        rob(new_tail).pc <= dispatch_inst(i).pc;
                        rob(new_tail).dest_reg <= dispatch_inst(i).dest_reg;
                        rob(new_tail).dest_preg <= dispatch_dest_preg(i);
                        rob(new_tail).old_preg <= dispatch_old_preg(i);
                        rob(new_tail).eu_type <= dispatch_inst(i).eu_type;
                        rob(new_tail).is_branch <= dispatch_inst(i).is_branch;
                        rob(new_tail).exception <= '0';

                        alloc_rob_index(i) <= new_tail;

                        -- Advance tail pointer
                        if new_tail = ROB_SIZE-1 then
                            new_tail := 0;
                        else
                            new_tail := new_tail + 1;
                        end if;

                        dispatch_count := dispatch_count + 1;
                    else
                        alloc_rob_index(i) <= 0;
                    end if;
                end loop;

                tail_ptr <= new_tail;

                -- =====================================================
                -- COMPLETION: Mark instructions as completed
                -- =====================================================
                for i in 0 to EU_COUNT-1 loop
                    if complete_valid(i) = '1' then
                        rob(complete_rob_idx(i)).status <= ROB_COMPLETED;
                        rob(complete_rob_idx(i)).result <= complete_result(i);
                        rob(complete_rob_idx(i)).exception <= complete_exception(i);
                    end if;
                end loop;

                -- =====================================================
                -- COMMIT: Retire completed instructions in order
                -- =====================================================
                commit_count := 0;
                new_head := head_ptr;

                for i in 0 to ISSUE_WIDTH-1 loop
                    if rob(new_head).valid = '1' and rob(new_head).status = ROB_COMPLETED then

                        -- Check for exceptions
                        if rob(new_head).exception = '1' then
                            exception_valid <= '1';
                            exception_pc <= rob(new_head).pc;
                            exception_vector <= rob(new_head).exception_vec;
                            flush_pipeline <= '1';

                            -- Flush all ROB entries
                            rob <= (others => ROB_ENTRY_INIT);
                            head_ptr <= 0;
                            tail_ptr <= 0;
                            entry_count <= 0;
                            exit;  -- Stop committing

                        -- Check for branch misprediction
                        elsif rob(new_head).is_branch = '1' then
                            -- Simplified: assume we check branch here
                            -- Real implementation would compare predicted vs actual
                            -- For now, assume no misprediction
                            null;
                        end if;

                        -- Commit the instruction
                        commit_valid(i) <= '1';
                        commit_dest_reg(i) <= rob(new_head).dest_reg;
                        commit_dest_preg(i) <= rob(new_head).dest_preg;
                        commit_old_preg(i) <= rob(new_head).old_preg;
                        commit_result(i) <= rob(new_head).result;
                        commit_pc(i) <= rob(new_head).pc;

                        -- Free ROB entry
                        rob(new_head).valid <= '0';
                        rob(new_head).status <= ROB_INVALID;

                        -- Advance head pointer
                        if new_head = ROB_SIZE-1 then
                            new_head := 0;
                        else
                            new_head := new_head + 1;
                        end if;

                        commit_count := commit_count + 1;

                    else
                        -- Can't commit out of order - stop
                        exit;
                    end if;
                end loop;

                head_ptr <= new_head;

                -- Update entry count
                entry_count <= entry_count + dispatch_count - commit_count;

            end if;
        end if;
    end process;

end rtl;
