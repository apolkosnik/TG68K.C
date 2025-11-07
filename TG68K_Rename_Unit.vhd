--------------------------------------------------------------------------------
-- TG68K Superscalar Register Rename Unit
-- Performs register renaming for out-of-order execution
-- Maps 16 architectural registers to 96 physical registers
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Superscalar_Pack.all;

entity TG68K_Rename_Unit is
    port (
        clk             : in std_logic;
        reset           : in std_logic;

        -- Input from decode stage
        decode_instr    : in instruction_array_t;
        decode_valid    : in std_logic_vector(ISSUE_WIDTH-1 downto 0);

        -- Control
        stall           : in std_logic;
        flush           : in std_logic;

        -- ROB allocation
        rob_head        : in integer range 0 to ROB_SIZE-1;
        rob_tail        : in integer range 0 to ROB_SIZE-1;
        rob_full        : in std_logic;

        -- Commit interface (for freeing physical registers)
        commit_valid    : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        commit_arch_reg : in commit_array_t;

        -- Output to reservation stations
        rename_instr    : out instruction_array_t;
        rename_valid    : out std_logic_vector(ISSUE_WIDTH-1 downto 0);

        -- Physical register file status
        phys_reg_ready  : in std_logic_vector(PHYS_REGS-1 downto 0)
    );
end entity TG68K_Rename_Unit;

architecture rtl of TG68K_Rename_Unit is

    -- Register rename table (architectural -> physical mapping)
    signal rename_map           : rename_map_t;
    signal rename_map_next      : rename_map_t;
    signal rename_map_committed : rename_map_t;  -- Committed state (for flush recovery)

    -- Free list for physical registers
    signal free_list                : free_list_t;
    signal free_list_head           : integer range 0 to PHYS_REGS-1;
    signal free_list_tail           : integer range 0 to PHYS_REGS-1;
    signal free_list_count          : integer range 0 to PHYS_REGS;
    signal free_list_head_committed : integer range 0 to PHYS_REGS-1;  -- Committed state
    signal free_list_tail_committed : integer range 0 to PHYS_REGS-1;  -- Committed state
    signal free_list_count_committed: integer range 0 to PHYS_REGS;    -- Committed state

    -- ROB allocation
    signal rob_alloc_ptr    : integer range 0 to ROB_SIZE-1;

begin

    -- =========================================================================
    -- Register Renaming
    -- =========================================================================
    process(clk, reset)
        variable alloc_count    : integer range 0 to ISSUE_WIDTH;
        variable new_phys_reg   : integer range 0 to PHYS_REGS-1;
        variable free_ptr       : integer range 0 to PHYS_REGS-1;
        variable rob_id         : integer range 0 to ROB_SIZE-1;
    begin
        if reset = '1' then
            -- Initialize rename map: arch reg i -> phys reg i (identity mapping)
            for i in 0 to ARCH_REGS-1 loop
                rename_map(i) <= i;
                rename_map_committed(i) <= i;
            end loop;

            -- Initialize free list: physical registers 16-95 are free
            free_list_head <= 16;
            free_list_tail <= 95;
            free_list_count <= PHYS_REGS - ARCH_REGS;
            free_list_head_committed <= 16;
            free_list_tail_committed <= 95;
            free_list_count_committed <= PHYS_REGS - ARCH_REGS;
            for i in 16 to PHYS_REGS-1 loop
                free_list(i - 16) <= i;
            end loop;

            rob_alloc_ptr <= 0;

            for i in 0 to ISSUE_WIDTH-1 loop
                rename_instr(i).valid <= '0';
                rename_valid(i) <= '0';
            end loop;

        elsif rising_edge(clk) then
            if flush = '1' then
                -- Flush pipeline - restore to committed state
                rename_map <= rename_map_committed;
                free_list_head <= free_list_head_committed;
                free_list_tail <= free_list_tail_committed;
                free_list_count <= free_list_count_committed;

                for i in 0 to ISSUE_WIDTH-1 loop
                    rename_instr(i).valid <= '0';
                    rename_valid(i) <= '0';
                end loop;

            elsif stall = '0' and rob_full = '0' then
                alloc_count := 0;
                free_ptr := free_list_head;
                rob_id := rob_tail;
                rename_map_next <= rename_map;

                -- Process up to 8 instructions
                for i in 0 to ISSUE_WIDTH-1 loop
                    if decode_valid(i) = '1' and alloc_count < free_list_count then
                        rename_instr(i) <= decode_instr(i);
                        rename_instr(i).valid <= '1';
                        rename_valid(i) <= '1';

                        -- Assign ROB entry
                        rename_instr(i).rob_id <= rob_id;
                        rob_id := (rob_id + 1) mod ROB_SIZE;

                        -- Rename source operands
                        if decode_instr(i).src1_valid = '1' then
                            rename_instr(i).src1_phys_reg <= rename_map_next(decode_instr(i).src1_arch_reg);
                            -- Check if source is ready
                            if phys_reg_ready(rename_map_next(decode_instr(i).src1_arch_reg)) = '1' then
                                rename_instr(i).src1_ready <= '1';
                            else
                                rename_instr(i).src1_ready <= '0';
                            end if;
                        else
                            rename_instr(i).src1_ready <= '1'; -- No source = ready
                        end if;

                        if decode_instr(i).src2_valid = '1' then
                            rename_instr(i).src2_phys_reg <= rename_map_next(decode_instr(i).src2_arch_reg);
                            if phys_reg_ready(rename_map_next(decode_instr(i).src2_arch_reg)) = '1' then
                                rename_instr(i).src2_ready <= '1';
                            else
                                rename_instr(i).src2_ready <= '0';
                            end if;
                        else
                            rename_instr(i).src2_ready <= '1';
                        end if;

                        -- Allocate new physical register for destination
                        if decode_instr(i).dest_valid = '1' then
                            -- Save old physical register mapping (for freeing on commit)
                            rename_instr(i).old_phys_reg <= rename_map_next(decode_instr(i).dest_arch_reg);

                            -- Get free physical register
                            new_phys_reg := free_list(free_ptr);
                            rename_instr(i).dest_phys_reg <= new_phys_reg;

                            -- Update rename map
                            rename_map_next(decode_instr(i).dest_arch_reg) := new_phys_reg;

                            -- Advance free list pointer
                            free_ptr := (free_ptr + 1) mod PHYS_REGS;
                            alloc_count := alloc_count + 1;
                        end if;

                    else
                        -- No valid instruction or out of resources
                        rename_instr(i).valid <= '0';
                        rename_valid(i) <= '0';
                    end if;
                end loop;

                -- Update rename map and free list
                rename_map <= rename_map_next;
                free_list_head <= free_ptr;
                free_list_count <= free_list_count - alloc_count;
                rob_alloc_ptr <= rob_id;

            else
                -- Stalled or ROB full
                for i in 0 to ISSUE_WIDTH-1 loop
                    rename_instr(i).valid <= '0';
                    rename_valid(i) <= '0';
                end loop;
            end if;

            -- Update committed state and free physical registers on commit
            for i in 0 to ISSUE_WIDTH-1 loop
                if commit_valid(i) = '1' and commit_arch_reg(i).valid = '1' then
                    -- Update committed rename map
                    rename_map_committed(commit_arch_reg(i).arch_reg) <= commit_arch_reg(i).phys_reg;

                    -- Add old physical register to free list
                    free_list(free_list_tail) <= commit_arch_reg(i).old_phys_reg;
                    free_list_tail <= (free_list_tail + 1) mod PHYS_REGS;
                    free_list_count <= free_list_count + 1;

                    -- Update committed free list state
                    free_list_tail_committed <= (free_list_tail + 1) mod PHYS_REGS;
                    free_list_count_committed <= free_list_count + 1;
                end if;
            end loop;
        end if;
    end process;

end architecture rtl;
