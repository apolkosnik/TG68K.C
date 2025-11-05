------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K SuperScalar Reservation Stations                                  --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Holds decoded instructions waiting for operands and execution units     --
-- Issues instructions to EUs when ready (out-of-order execution)          --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_ReservationStation is
    port(
        clk             : in std_logic;
        reset           : in std_logic;
        enable          : in std_logic;

        -- Dispatch interface (from decode/rename)
        dispatch_valid  : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        dispatch_inst   : in decoded_inst_array_t;
        dispatch_rob_idx: in array(0 to ISSUE_WIDTH-1) of integer range 0 to ROB_SIZE-1;
        dispatch_src1_preg : in array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
        dispatch_src2_preg : in array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
        dispatch_dest_preg : in array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);

        rs_full         : out std_logic;

        -- Physical register file read
        prf_read_addr   : out array(0 to ISSUE_WIDTH*2-1) of std_logic_vector(5 downto 0);
        prf_read_data   : in array(0 to ISSUE_WIDTH*2-1) of std_logic_vector(31 downto 0);

        -- Result broadcast (from execution units - for forwarding)
        broadcast_valid : in std_logic_vector(EU_COUNT-1 downto 0);
        broadcast_preg  : in array(0 to EU_COUNT-1) of std_logic_vector(5 downto 0);
        broadcast_data  : in array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);

        -- Issue to execution units
        issue_valid     : out std_logic_vector(EU_COUNT-1 downto 0);
        issue_opcode    : out array(0 to EU_COUNT-1) of std_logic_vector(15 downto 0);
        issue_pc        : out array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
        issue_rob_idx   : out array(0 to EU_COUNT-1) of integer range 0 to ROB_SIZE-1;
        issue_src1      : out array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
        issue_src2      : out array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
        issue_imm       : out array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);

        eu_busy         : in std_logic_vector(EU_COUNT-1 downto 0);

        -- Flush on branch misprediction
        flush           : in std_logic
    );
end TG68K_ReservationStation;

architecture rtl of TG68K_ReservationStation is

    signal rs           : rs_array_t;
    signal entry_count  : integer range 0 to RS_SIZE;
    signal is_full      : std_logic;

begin

    rs_full <= is_full;

    -- Check if RS is full
    process(entry_count)
    begin
        if entry_count >= (RS_SIZE - ISSUE_WIDTH) then
            is_full <= '1';
        else
            is_full <= '0';
        end if;
    end process;

    -- Main reservation station logic
    process(clk, reset)
        variable dispatch_count : integer;
        variable issue_count : array(0 to EU_COUNT-1) of integer;
        variable issued : array(0 to RS_SIZE-1) of std_logic;
    begin
        if reset = '1' then
            rs <= (others => RS_ENTRY_INIT);
            entry_count <= 0;
            issue_valid <= (others => '0');

        elsif rising_edge(clk) then

            if enable = '1' then

                issue_valid <= (others => '0');
                issued := (others => '0');

                -- Handle flush
                if flush = '1' then
                    rs <= (others => RS_ENTRY_INIT);
                    entry_count <= 0;
                else

                    -- =====================================================
                    -- WAKEUP: Update operand ready status from broadcasts
                    -- =====================================================
                    for i in 0 to RS_SIZE-1 loop
                        if rs(i).valid = '1' then
                            -- Check if source operands are now ready
                            for j in 0 to EU_COUNT-1 loop
                                if broadcast_valid(j) = '1' then
                                    -- Source 1 ready?
                                    if rs(i).src1_ready = '0' and rs(i).src1_preg = broadcast_preg(j) then
                                        rs(i).src1_ready <= '1';
                                        rs(i).src1_value <= broadcast_data(j);
                                    end if;

                                    -- Source 2 ready?
                                    if rs(i).src2_ready = '0' and rs(i).src2_preg = broadcast_preg(j) then
                                        rs(i).src2_ready <= '1';
                                        rs(i).src2_value <= broadcast_data(j);
                                    end if;
                                end if;
                            end loop;
                        end if;
                    end loop;

                    -- =====================================================
                    -- ISSUE: Select ready instructions and issue to EUs
                    -- =====================================================
                    for eu in 0 to EU_COUNT-1 loop
                        if eu_busy(eu) = '0' then
                            -- Find oldest ready instruction for this EU
                            for i in 0 to RS_SIZE-1 loop
                                if rs(i).valid = '1' and
                                   rs(i).eu_type = eu and
                                   rs(i).src1_ready = '1' and
                                   rs(i).src2_ready = '1' and
                                   issued(i) = '0' then

                                    -- Issue to EU
                                    issue_valid(eu) <= '1';
                                    issue_opcode(eu) <= rs(i).opcode;
                                    issue_pc(eu) <= rs(i).pc;
                                    issue_rob_idx(eu) <= rs(i).rob_index;
                                    issue_src1(eu) <= rs(i).src1_value;
                                    issue_src2(eu) <= rs(i).src2_value;
                                    issue_imm(eu) <= rs(i).immediate;

                                    -- Free RS entry
                                    rs(i).valid <= '0';
                                    issued(i) := '1';
                                    entry_count <= entry_count - 1;

                                    exit;  -- Only issue one instruction per EU
                                end if;
                            end loop;
                        end if;
                    end loop;

                    -- =====================================================
                    -- DISPATCH: Allocate RS entries for new instructions
                    -- =====================================================
                    dispatch_count := 0;

                    for i in 0 to ISSUE_WIDTH-1 loop
                        if dispatch_valid(i) = '1' and is_full = '0' then
                            -- Find free RS entry
                            for j in 0 to RS_SIZE-1 loop
                                if rs(j).valid = '0' then
                                    rs(j).valid <= '1';
                                    rs(j).opcode <= dispatch_inst(i).opcode;
                                    rs(j).pc <= dispatch_inst(i).pc;
                                    rs(j).rob_index <= dispatch_rob_idx(i);
                                    rs(j).eu_type <= dispatch_inst(i).eu_type;
                                    rs(j).immediate <= dispatch_inst(i).immediate;
                                    rs(j).is_branch <= dispatch_inst(i).is_branch;
                                    rs(j).is_load <= dispatch_inst(i).is_load;
                                    rs(j).is_store <= dispatch_inst(i).is_store;

                                    -- Setup source operands
                                    rs(j).src1_preg <= dispatch_src1_preg(i);
                                    rs(j).src2_preg <= dispatch_src2_preg(i);
                                    rs(j).dest_preg <= dispatch_dest_preg(i);

                                    -- Read operands from physical register file
                                    -- (simplified - actual implementation would track ready status)
                                    rs(j).src1_ready <= '1';  -- Assume ready for now
                                    rs(j).src2_ready <= '1';
                                    rs(j).src1_value <= prf_read_data(i*2);
                                    rs(j).src2_value <= prf_read_data(i*2 + 1);

                                    dispatch_count := dispatch_count + 1;
                                    entry_count <= entry_count + 1;

                                    exit;  -- Found free entry
                                end if;
                            end loop;
                        end if;
                    end loop;

                end if;

            end if;
        end if;
    end process;

    -- Generate PRF read addresses
    process(dispatch_valid, dispatch_src1_preg, dispatch_src2_preg)
    begin
        for i in 0 to ISSUE_WIDTH-1 loop
            if dispatch_valid(i) = '1' then
                prf_read_addr(i*2) <= dispatch_src1_preg(i);
                prf_read_addr(i*2 + 1) <= dispatch_src2_preg(i);
            else
                prf_read_addr(i*2) <= (others => '0');
                prf_read_addr(i*2 + 1) <= (others => '0');
            end if;
        end loop;
    end process;

end rtl;
