------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K SuperScalar Decode Unit (4-way parallel)                          --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Decodes up to 4 instructions in parallel                                --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_Decode is
    port(
        clk             : in std_logic;
        reset           : in std_logic;
        enable          : in std_logic;

        -- Input from fetch stage
        fetch_valid     : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        fetch_pc        : in std_logic_vector(31 downto 0);
        fetch_inst      : in fetch_buffer_t;

        -- Decoded outputs
        decoded_valid   : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
        decoded_inst    : out decoded_inst_array_t;

        -- Control
        decode_stall    : in std_logic
    );
end TG68K_Decode;

architecture rtl of TG68K_Decode is

    -- Function to decode a single 68K instruction
    function decode_68k_inst(
        opcode : std_logic_vector(15 downto 0);
        pc     : std_logic_vector(31 downto 0)
    ) return decoded_inst_t is
        variable result : decoded_inst_t;
        variable op_high : std_logic_vector(3 downto 0);
        variable op_mid  : std_logic_vector(2 downto 0);
    begin
        result := DECODED_INST_INIT;
        result.valid := '1';
        result.pc := pc;
        result.opcode := opcode;

        op_high := opcode(15 downto 12);
        op_mid := opcode(8 downto 6);

        -- Basic instruction type decoding (simplified for demonstration)
        case op_high is
            -- MOVE instructions (00xx, 01xx, 10xx, 11xx for byte/word/long)
            when "0001" | "0010" | "0011" =>
                result.inst_type := x"0";  -- MOVE
                result.eu_type := EU_ALU0;
                result.src_reg1 := opcode(3 downto 0);
                result.dest_reg := opcode(11 downto 9);
                result.uses_src1 := '1';
                result.writes_dest := '1';

                -- Check for memory operations
                if opcode(5 downto 3) = "010" or opcode(5 downto 3) = "011" or
                   opcode(5 downto 3) = "100" or opcode(5 downto 3) = "101" or
                   opcode(5 downto 3) = "110" or opcode(5 downto 3) = "111" then
                    result.is_load := '1';
                    result.eu_type := EU_LSU;
                end if;

                if opcode(8 downto 6) = "010" or opcode(8 downto 6) = "011" or
                   opcode(8 downto 6) = "100" or opcode(8 downto 6) = "101" then
                    result.is_store := '1';
                    result.eu_type := EU_LSU;
                end if;

            -- ADD/SUB instructions
            when "1101" =>  -- ADD
                result.inst_type := x"1";  -- ADD
                result.eu_type := EU_ALU0;
                result.src_reg1 := opcode(2 downto 0);
                result.src_reg2 := opcode(11 downto 9);
                result.dest_reg := opcode(11 downto 9);
                result.uses_src1 := '1';
                result.uses_src2 := '1';
                result.writes_dest := '1';

            when "1001" =>  -- SUB
                result.inst_type := x"2";  -- SUB
                result.eu_type := EU_ALU0;
                result.src_reg1 := opcode(2 downto 0);
                result.src_reg2 := opcode(11 downto 9);
                result.dest_reg := opcode(11 downto 9);
                result.uses_src1 := '1';
                result.uses_src2 := '1';
                result.writes_dest := '1';

            -- AND/OR/EOR instructions
            when "1100" =>  -- AND
                result.inst_type := x"3";
                result.eu_type := EU_ALU1;
                result.src_reg1 := opcode(2 downto 0);
                result.src_reg2 := opcode(11 downto 9);
                result.dest_reg := opcode(11 downto 9);
                result.uses_src1 := '1';
                result.uses_src2 := '1';
                result.writes_dest := '1';

            when "1000" =>  -- OR
                result.inst_type := x"4";
                result.eu_type := EU_ALU1;
                result.src_reg1 := opcode(2 downto 0);
                result.src_reg2 := opcode(11 downto 9);
                result.dest_reg := opcode(11 downto 9);
                result.uses_src1 := '1';
                result.uses_src2 := '1';
                result.writes_dest := '1';

            when "1011" =>  -- EOR/CMP
                result.inst_type := x"5";
                result.eu_type := EU_ALU1;
                result.src_reg1 := opcode(2 downto 0);
                result.src_reg2 := opcode(11 downto 9);
                result.dest_reg := opcode(11 downto 9);
                result.uses_src1 := '1';
                result.uses_src2 := '1';
                result.writes_dest := '1';

            -- Branch instructions
            when "0110" =>  -- Bcc (branch on condition)
                result.inst_type := x"6";
                result.eu_type := EU_BRANCH;
                result.is_branch := '1';
                result.displacement := (31 downto 8 => opcode(7)) & opcode(7 downto 0);
                result.uses_src1 := '0';
                result.uses_src2 := '0';
                result.writes_dest := '0';

            -- MOVEQ (move quick - immediate)
            when "0111" =>
                result.inst_type := x"7";
                result.eu_type := EU_ALU0;
                result.dest_reg := opcode(11 downto 9);
                result.immediate := (31 downto 8 => opcode(7)) & opcode(7 downto 0);
                result.uses_src1 := '0';
                result.uses_src2 := '0';
                result.writes_dest := '1';

            -- Other instructions
            when others =>
                result.inst_type := x"F";  -- Other/complex
                result.eu_type := EU_ALU0;
                result.uses_src1 := '0';
                result.uses_src2 := '0';
                result.writes_dest := '0';
        end case;

        return result;
    end function;

begin

    process(clk, reset)
        variable current_pc : std_logic_vector(31 downto 0);
    begin
        if reset = '1' then
            decoded_valid <= (others => '0');
            decoded_inst <= (others => DECODED_INST_INIT);

        elsif rising_edge(clk) then
            if enable = '1' and decode_stall = '0' then

                current_pc := fetch_pc;

                -- Decode all 4 instructions in parallel
                for i in 0 to ISSUE_WIDTH-1 loop
                    if fetch_valid(i) = '1' then
                        decoded_inst(i) <= decode_68k_inst(fetch_inst(i), current_pc);
                        decoded_valid(i) <= '1';
                        -- Increment PC for next instruction (assuming 2 bytes per inst)
                        current_pc := std_logic_vector(unsigned(current_pc) + 2);
                    else
                        decoded_inst(i) <= DECODED_INST_INIT;
                        decoded_valid(i) <= '0';
                    end if;
                end loop;

            else
                -- Stalled - hold current values
                null;
            end if;
        end if;
    end process;

end rtl;
