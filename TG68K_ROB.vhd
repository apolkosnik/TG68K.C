--------------------------------------------------------------------------------
-- TG68K Superscalar Reorder Buffer (ROB)
-- Maintains program order and ensures in-order commit
-- 128 entries, circular queue
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Superscalar_Pack.all;

entity TG68K_ROB is
    port (
        clk             : in std_logic;
        reset           : in std_logic;

        -- Allocation from rename stage
        alloc_valid     : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        alloc_instr     : in instruction_array_t;

        -- Completion from execution units
        complete_valid  : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        complete_result : in exec_result_array_t;

        -- Commit interface
        commit_valid    : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
        commit_data     : out commit_array_t;

        -- Branch misprediction
        branch_mispredict : out std_logic;
        branch_flush_pc   : out std_logic_vector(31 downto 0);

        -- ROB status
        rob_full        : out std_logic;
        rob_head        : out integer range 0 to ROB_SIZE-1;
        rob_tail        : out integer range 0 to ROB_SIZE-1;

        -- Exception handling
        exception       : out std_logic;
        exception_vec   : out std_logic_vector(7 downto 0);
        exception_pc    : out std_logic_vector(31 downto 0)
    );
end entity TG68K_ROB;

architecture rtl of TG68K_ROB is

    -- ROB storage
    signal rob          : rob_array_t;

    -- ROB pointers
    signal head_ptr     : integer range 0 to ROB_SIZE-1;
    signal tail_ptr     : integer range 0 to ROB_SIZE-1;
    signal count        : integer range 0 to ROB_SIZE;

begin

    rob_head <= head_ptr;
    rob_tail <= tail_ptr;
    rob_full <= '1' when count >= (ROB_SIZE - ISSUE_WIDTH) else '0';

    -- =========================================================================
    -- ROB Management
    -- =========================================================================
    process(clk, reset)
        variable alloc_count    : integer range 0 to ISSUE_WIDTH;
        variable commit_count   : integer range 0 to ISSUE_WIDTH;
        variable next_head      : integer range 0 to ROB_SIZE-1;
        variable next_tail      : integer range 0 to ROB_SIZE-1;
    begin
        if reset = '1' then
            head_ptr <= 0;
            tail_ptr <= 0;
            count <= 0;

            for i in 0 to ROB_SIZE-1 loop
                rob(i).valid <= '0';
                rob(i).complete <= '0';
            end loop;

            for i in 0 to ISSUE_WIDTH-1 loop
                commit_valid(i) <= '0';
            end loop;

            branch_mispredict <= '0';
            exception <= '0';

        elsif rising_edge(clk) then
            alloc_count := 0;
            commit_count := 0;
            next_head := head_ptr;
            next_tail := tail_ptr;

            branch_mispredict <= '0';
            exception <= '0';

            -- =====================================================
            -- Allocation: Add new instructions to ROB
            -- =====================================================
            for i in 0 to ISSUE_WIDTH-1 loop
                if alloc_valid(i) = '1' then
                    rob(next_tail).valid <= '1';
                    rob(next_tail).complete <= '0';
                    rob(next_tail).pc <= alloc_instr(i).pc;
                    rob(next_tail).operation <= alloc_instr(i).operation;
                    rob(next_tail).dest_valid <= alloc_instr(i).dest_valid;
                    rob(next_tail).dest_arch_reg <= alloc_instr(i).dest_arch_reg;
                    rob(next_tail).dest_phys_reg <= alloc_instr(i).dest_phys_reg;
                    rob(next_tail).is_branch <= alloc_instr(i).is_branch;
                    rob(next_tail).exception <= '0';

                    next_tail := (next_tail + 1) mod ROB_SIZE;
                    alloc_count := alloc_count + 1;
                end if;
            end loop;

            -- =====================================================
            -- Completion: Mark instructions as complete
            -- =====================================================
            for i in 0 to ISSUE_WIDTH-1 loop
                if complete_valid(i) = '1' then
                    rob(complete_result(i).rob_id).complete <= '1';
                    rob(complete_result(i).rob_id).result <= complete_result(i).result;

                    -- Branch resolution
                    if complete_result(i).is_branch = '1' then
                        rob(complete_result(i).rob_id).branch_taken <= complete_result(i).branch_taken;
                        rob(complete_result(i).rob_id).branch_target <= complete_result(i).branch_target;
                        rob(complete_result(i).rob_id).branch_mispred <= complete_result(i).branch_mispred;

                        -- Flush on branch misprediction
                        if complete_result(i).branch_mispred = '1' then
                            branch_mispredict <= '1';
                            branch_flush_pc <= complete_result(i).branch_target;
                        end if;
                    end if;

                    -- Exception handling
                    if complete_result(i).exception = '1' then
                        rob(complete_result(i).rob_id).exception <= '1';
                        rob(complete_result(i).rob_id).exception_vec <= complete_result(i).exception_vec;
                    end if;
                end if;
            end loop;

            -- =====================================================
            -- Commit: Retire instructions in program order
            -- =====================================================
            for i in 0 to ISSUE_WIDTH-1 loop
                commit_valid(i) <= '0';

                if rob(next_head).valid = '1' and rob(next_head).complete = '1' then
                    -- Check for exception
                    if rob(next_head).exception = '1' then
                        exception <= '1';
                        exception_vec <= rob(next_head).exception_vec;
                        exception_pc <= rob(next_head).pc;
                        -- Stop committing on exception
                        exit;
                    end if;

                    -- Commit this instruction
                    commit_valid(i) <= '1';
                    commit_data(i).valid <= '1';
                    commit_data(i).arch_reg <= rob(next_head).dest_arch_reg;
                    commit_data(i).phys_reg <= rob(next_head).dest_phys_reg;
                    commit_data(i).data <= rob(next_head).result;

                    -- Free ROB entry
                    rob(next_head).valid <= '0';
                    rob(next_head).complete <= '0';

                    next_head := (next_head + 1) mod ROB_SIZE;
                    commit_count := commit_count + 1;

                else
                    -- Can't commit this instruction yet - stop
                    exit;
                end if;
            end loop;

            -- Update pointers and count
            head_ptr <= next_head;
            tail_ptr <= next_tail;
            count <= count + alloc_count - commit_count;

        end if;
    end process;

end architecture rtl;
