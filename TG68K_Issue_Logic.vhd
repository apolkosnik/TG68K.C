--------------------------------------------------------------------------------
-- TG68K Superscalar Issue Logic and Reservation Stations
-- Holds instructions waiting for operands and issues to execution units
-- 8 unified reservation stations with 16 entries each (total 128 entries)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Superscalar_Pack.all;

entity TG68K_Issue_Logic is
    port (
        clk             : in std_logic;
        reset           : in std_logic;

        -- Input from rename stage
        rename_instr    : in instruction_array_t;
        rename_valid    : in std_logic_vector(ISSUE_WIDTH-1 downto 0);

        -- Physical register file (for operand read)
        phys_reg_file   : in phys_reg_file_t;

        -- Forwarding from execution units
        forward_valid   : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        forward_result  : in exec_result_array_t;

        -- Control
        stall           : in std_logic;
        flush           : in std_logic;

        -- Issue to execution units (8-way issue)
        issue_valid     : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
        issue_instr     : out instruction_array_t;
        issue_src1      : out exec_result_array_t; -- Operand values
        issue_src2      : out exec_result_array_t;

        -- Execution unit busy signals
        exec_busy       : in std_logic_vector(ISSUE_WIDTH-1 downto 0);

        -- Status
        rs_full         : out std_logic
    );
end entity TG68K_Issue_Logic;

architecture rtl of TG68K_Issue_Logic is

    -- Unified reservation station (128 entries total)
    signal rs           : rs_array_t;
    signal rs_valid     : std_logic_vector(RS_SIZE*ISSUE_WIDTH-1 downto 0);
    signal rs_count     : integer range 0 to RS_SIZE*ISSUE_WIDTH;

    -- Issue selection
    type issue_select_t is array (0 to ISSUE_WIDTH-1) of integer range 0 to RS_SIZE*ISSUE_WIDTH-1;
    signal issue_select : issue_select_t;

begin

    rs_full <= '1' when rs_count >= (RS_SIZE*ISSUE_WIDTH - ISSUE_WIDTH) else '0';

    -- =========================================================================
    -- Reservation Station Management
    -- =========================================================================
    process(clk, reset)
        variable alloc_ptr      : integer range 0 to RS_SIZE*ISSUE_WIDTH-1;
        variable alloc_count    : integer range 0 to ISSUE_WIDTH;
        variable issue_count    : integer range 0 to ISSUE_WIDTH;
    begin
        if reset = '1' then
            for i in 0 to RS_SIZE*ISSUE_WIDTH-1 loop
                rs(i).valid <= '0';
                rs(i).issued <= '0';
                rs_valid(i) <= '0';
            end loop;
            rs_count <= 0;

            for i in 0 to ISSUE_WIDTH-1 loop
                issue_valid(i) <= '0';
            end loop;

        elsif rising_edge(clk) then
            if flush = '1' then
                -- Flush all RS entries
                for i in 0 to RS_SIZE*ISSUE_WIDTH-1 loop
                    rs(i).valid <= '0';
                    rs(i).issued <= '0';
                    rs_valid(i) <= '0';
                end loop;
                rs_count <= 0;

                for i in 0 to ISSUE_WIDTH-1 loop
                    issue_valid(i) <= '0';
                end loop;

            elsif stall = '0' then
                alloc_ptr := 0;
                alloc_count := 0;

                -- =====================================================
                -- Allocate: Add instructions to reservation stations
                -- =====================================================
                for i in 0 to ISSUE_WIDTH-1 loop
                    if rename_valid(i) = '1' then
                        -- Find free RS entry
                        for j in 0 to RS_SIZE*ISSUE_WIDTH-1 loop
                            if rs_valid(alloc_ptr) = '0' then
                                rs(alloc_ptr).valid <= '1';
                                rs(alloc_ptr).issued <= '0';
                                rs(alloc_ptr).instruction <= rename_instr(i);
                                rs(alloc_ptr).age <= rename_instr(i).rob_id;

                                -- Get source operands
                                if rename_instr(i).src1_valid = '1' then
                                    if rename_instr(i).src1_ready = '1' then
                                        rs(alloc_ptr).src1_value <= phys_reg_file(rename_instr(i).src1_phys_reg).data;
                                    else
                                        rs(alloc_ptr).src1_value <= (others => '0');
                                    end if;
                                end if;

                                if rename_instr(i).src2_valid = '1' then
                                    if rename_instr(i).src2_ready = '1' then
                                        rs(alloc_ptr).src2_value <= phys_reg_file(rename_instr(i).src2_phys_reg).data;
                                    else
                                        rs(alloc_ptr).src2_value <= (others => '0');
                                    end if;
                                end if;

                                rs_valid(alloc_ptr) <= '1';
                                alloc_count := alloc_count + 1;
                                alloc_ptr := (alloc_ptr + 1) mod (RS_SIZE*ISSUE_WIDTH);
                                exit;
                            else
                                alloc_ptr := (alloc_ptr + 1) mod (RS_SIZE*ISSUE_WIDTH);
                            end if;
                        end loop;
                    end if;
                end loop;

                -- =====================================================
                -- Wakeup: Update operands from forwarding network
                -- =====================================================
                for i in 0 to RS_SIZE*ISSUE_WIDTH-1 loop
                    if rs_valid(i) = '1' and rs(i).issued = '0' then
                        -- Check forwarding for source 1
                        if rs(i).instruction.src1_valid = '1' and rs(i).instruction.src1_ready = '0' then
                            for j in 0 to ISSUE_WIDTH-1 loop
                                if forward_valid(j) = '1' and
                                   forward_result(j).dest_phys_reg = rs(i).instruction.src1_phys_reg then
                                    rs(i).src1_value <= forward_result(j).result;
                                    rs(i).instruction.src1_ready <= '1';
                                end if;
                            end loop;
                        end if;

                        -- Check forwarding for source 2
                        if rs(i).instruction.src2_valid = '1' and rs(i).instruction.src2_ready = '0' then
                            for j in 0 to ISSUE_WIDTH-1 loop
                                if forward_valid(j) = '1' and
                                   forward_result(j).dest_phys_reg = rs(i).instruction.src2_phys_reg then
                                    rs(i).src2_value <= forward_result(j).result;
                                    rs(i).instruction.src2_ready <= '1';
                                end if;
                            end loop;
                        end if;
                    end if;
                end loop;

                -- =====================================================
                -- Select: Choose instructions to issue (oldest-first)
                -- =====================================================
                issue_count := 0;

                for i in 0 to ISSUE_WIDTH-1 loop
                    issue_valid(i) <= '0';
                    issue_select(i) <= 0;
                end loop;

                -- Find ready instructions for each execution unit type
                for exec_unit_idx in 0 to ISSUE_WIDTH-1 loop
                    if exec_busy(exec_unit_idx) = '0' then
                        -- Find oldest ready instruction for this unit type
                        for i in 0 to RS_SIZE*ISSUE_WIDTH-1 loop
                            if rs_valid(i) = '1' and
                               rs(i).issued = '0' and
                               rs(i).instruction.src1_ready = '1' and
                               rs(i).instruction.src2_ready = '1' then

                                -- Issue this instruction
                                issue_valid(exec_unit_idx) <= '1';
                                issue_select(exec_unit_idx) <= i;
                                issue_instr(exec_unit_idx) <= rs(i).instruction;

                                -- Set operand values
                                issue_src1(exec_unit_idx).result <= rs(i).src1_value;
                                issue_src2(exec_unit_idx).result <= rs(i).src2_value;

                                -- Mark as issued
                                rs(i).issued <= '1';
                                issue_count := issue_count + 1;
                                exit;
                            end if;
                        end loop;
                    end if;
                end loop;

                -- =====================================================
                -- Remove: Free RS entries after issue
                -- =====================================================
                for i in 0 to RS_SIZE*ISSUE_WIDTH-1 loop
                    if rs(i).issued = '1' then
                        rs(i).valid <= '0';
                        rs(i).issued <= '0';
                        rs_valid(i) <= '0';
                    end if;
                end loop;

                -- Update count
                rs_count <= rs_count + alloc_count - issue_count;
            end if;
        end if;
    end process;

end architecture rtl;
