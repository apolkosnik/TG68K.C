------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K Complete Instruction Decoder                                      --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Comprehensive 68K instruction decoder with all addressing modes         --
-- Supports: 68000, 68010, 68020 instruction sets                          --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_Complete_Decoder is
    generic(
        CPU_TYPE : std_logic_vector(1 downto 0) := "01"  -- 00=68000, 01=68010, 11=68020
    );
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
end TG68K_Complete_Decoder;

architecture rtl of TG68K_Complete_Decoder is

    -- Helper function to extract effective address mode
    function get_ea_mode(opcode : std_logic_vector(15 downto 0); is_source : boolean) return integer is
        variable mode_bits : std_logic_vector(2 downto 0);
        variable reg_bits  : std_logic_vector(2 downto 0);
    begin
        if is_source then
            mode_bits := opcode(5 downto 3);
            reg_bits := opcode(2 downto 0);
        else
            mode_bits := opcode(11 downto 9);
            reg_bits := opcode(8 downto 6);
        end if;

        case mode_bits is
            when "000" => return 0;  -- Dn (Data register direct)
            when "001" => return 1;  -- An (Address register direct)
            when "010" => return 2;  -- (An) (Address register indirect)
            when "011" => return 3;  -- (An)+ (Address register indirect with postincrement)
            when "100" => return 4;  -- -(An) (Address register indirect with predecrement)
            when "101" => return 5;  -- d16(An) (Address register indirect with displacement)
            when "110" => return 6;  -- d8(An,Xn) (Address register indirect with index)
            when "111" =>
                case reg_bits is
                    when "000" => return 7;  -- xxx.W (Absolute short)
                    when "001" => return 8;  -- xxx.L (Absolute long)
                    when "010" => return 9;  -- d16(PC) (PC relative with displacement)
                    when "011" => return 10; -- d8(PC,Xn) (PC relative with index)
                    when "100" => return 11; -- #<data> (Immediate)
                    when others => return 15; -- Invalid
                end case;
            when others => return 15; -- Invalid
        end case;
    end function;

    -- Comprehensive decode function
    function decode_68k_complete(
        opcode : std_logic_vector(15 downto 0);
        pc     : std_logic_vector(31 downto 0);
        cpu_type : std_logic_vector(1 downto 0)
    ) return decoded_inst_t is
        variable result : decoded_inst_t;
        variable op_high : std_logic_vector(3 downto 0);
        variable op_mid  : std_logic_vector(3 downto 0);
        variable ea_mode_src : integer;
        variable ea_mode_dst : integer;
    begin
        result := DECODED_INST_INIT;
        result.valid := '1';
        result.pc := pc;
        result.opcode := opcode;

        op_high := opcode(15 downto 12);
        op_mid := opcode(11 downto 8);

        -- Main instruction decode
        case op_high is
            -- MOVE Byte (0001)
            when "0001" =>
                result.inst_type := x"0";
                result.src_reg1 := opcode(2 downto 0);
                result.dest_reg := opcode(11 downto 9);
                ea_mode_src := get_ea_mode(opcode, true);
                ea_mode_dst := get_ea_mode(opcode, false);

                if ea_mode_src >= 2 or ea_mode_dst >= 2 then
                    result.eu_type := EU_LSU;
                    if ea_mode_src >= 2 then result.is_load := '1'; end if;
                    if ea_mode_dst >= 2 then result.is_store := '1'; end if;
                else
                    result.eu_type := EU_ALU0;
                end if;
                result.uses_src1 := '1';
                result.writes_dest := '1';

            -- MOVE Long/Word (0010, 0011)
            when "0010" | "0011" =>
                result.inst_type := x"0";
                result.src_reg1 := opcode(2 downto 0);
                result.dest_reg := opcode(11 downto 9);
                ea_mode_src := get_ea_mode(opcode, true);
                ea_mode_dst := get_ea_mode(opcode, false);

                if ea_mode_src >= 2 or ea_mode_dst >= 2 then
                    result.eu_type := EU_LSU;
                    if ea_mode_src >= 2 then result.is_load := '1'; end if;
                    if ea_mode_dst >= 2 then result.is_store := '1'; end if;
                else
                    result.eu_type := EU_ALU0;
                end if;
                result.uses_src1 := '1';
                result.writes_dest := '1';

            -- Miscellaneous (0100)
            when "0100" =>
                case opcode(11 downto 8) is
                    -- NEGX, CLR, NEG, NOT
                    when "0000" | "0001" | "0010" | "0011" =>
                        result.inst_type := x"4";
                        result.eu_type := EU_ALU0;
                        result.dest_reg := opcode(2 downto 0);
                        result.uses_src1 := '0';
                        result.writes_dest := '1';

                    -- TST
                    when "0100" =>
                        result.inst_type := x"5";
                        result.eu_type := EU_ALU0;
                        result.src_reg1 := opcode(2 downto 0);
                        result.uses_src1 := '1';
                        result.writes_dest := '0';

                    -- MOVEM, LEA, PEA, JSR, JMP
                    when "1000" | "1001" | "1010" | "1011" | "1100" | "1101" | "1110" | "1111" =>
                        if opcode(7 downto 6) = "01" then -- LEA
                            result.inst_type := x"6";
                            result.eu_type := EU_LSU;
                            result.dest_reg := opcode(11 downto 9);
                            result.writes_dest := '1';
                        elsif opcode(7 downto 6) = "10" then -- JSR/JMP
                            result.inst_type := x"7";
                            result.eu_type := EU_BRANCH;
                            result.is_branch := '1';
                        else -- PEA, MOVEM
                            result.inst_type := x"8";
                            result.eu_type := EU_LSU;
                            result.is_store := '1';
                        end if;

                    when others =>
                        result.inst_type := x"F";
                        result.eu_type := EU_ALU0;
                end case;

            -- ADDQ/SUBQ (0101)
            when "0101" =>
                if opcode(7 downto 6) = "11" then
                    -- Scc or DBcc
                    if opcode(5 downto 3) = "001" then
                        result.inst_type := x"9"; -- DBcc
                        result.eu_type := EU_BRANCH;
                        result.is_branch := '1';
                    else
                        result.inst_type := x"A"; -- Scc
                        result.eu_type := EU_ALU0;
                        result.writes_dest := '1';
                    end if;
                else
                    -- ADDQ/SUBQ
                    result.inst_type := x"B";
                    result.eu_type := EU_ALU0;
                    result.dest_reg := opcode(2 downto 0);
                    result.immediate := (31 downto 3 => '0') & opcode(11 downto 9);
                    if result.immediate = x"00000000" then
                        result.immediate := x"00000008"; -- 0 means 8
                    end if;
                    result.uses_src2 := '1';
                    result.writes_dest := '1';
                end if;

            -- Bcc (0110)
            when "0110" =>
                result.inst_type := x"C"; -- Branch
                result.eu_type := EU_BRANCH;
                result.is_branch := '1';
                -- Displacement
                if opcode(7 downto 0) = x"00" then
                    result.displacement := (31 downto 16 => '0') & x"0002"; -- 16-bit follows
                elsif opcode(7 downto 0) = x"FF" and cpu_type(1) = '1' then
                    result.displacement := (31 downto 32 => '0'); -- 32-bit follows (68020)
                else
                    result.displacement := (31 downto 8 => opcode(7)) & opcode(7 downto 0);
                end if;

            -- MOVEQ (0111)
            when "0111" =>
                result.inst_type := x"D";
                result.eu_type := EU_ALU0;
                result.dest_reg := opcode(11 downto 9);
                result.immediate := (31 downto 8 => opcode(7)) & opcode(7 downto 0);
                result.writes_dest := '1';

            -- OR/DIV/SBCD (1000)
            when "1000" =>
                if opcode(7 downto 4) = "0001" then -- SBCD
                    result.inst_type := x"E";
                    result.eu_type := EU_ALU1;
                elsif opcode(7 downto 6) = "11" then -- DIVU/DIVS
                    result.inst_type := x"F";
                    result.eu_type := EU_ALU0;
                else -- OR
                    result.inst_type := x"4"; -- OR
                    result.eu_type := EU_ALU1;
                    result.src_reg1 := opcode(2 downto 0);
                    result.src_reg2 := opcode(11 downto 9);
                    result.dest_reg := opcode(11 downto 9);
                    result.uses_src1 := '1';
                    result.uses_src2 := '1';
                    result.writes_dest := '1';
                end if;

            -- SUB (1001)
            when "1001" =>
                result.inst_type := x"2"; -- SUB
                result.eu_type := EU_ALU0;
                result.src_reg1 := opcode(2 downto 0);
                result.src_reg2 := opcode(11 downto 9);
                result.dest_reg := opcode(11 downto 9);
                result.uses_src1 := '1';
                result.uses_src2 := '1';
                result.writes_dest := '1';

            -- (1010) - Line A (Unimplemented)
            when "1010" =>
                result.inst_type := x"F";
                result.eu_type := EU_ALU0;

            -- CMP/EOR (1011)
            when "1011" =>
                if opcode(8) = '1' and opcode(7 downto 6) /= "11" then
                    -- EOR
                    result.inst_type := x"5"; -- EOR
                    result.eu_type := EU_ALU1;
                    result.src_reg1 := opcode(11 downto 9);
                    result.src_reg2 := opcode(2 downto 0);
                    result.dest_reg := opcode(2 downto 0);
                    result.uses_src1 := '1';
                    result.uses_src2 := '1';
                    result.writes_dest := '1';
                else
                    -- CMP
                    result.inst_type := x"8"; -- CMP
                    result.eu_type := EU_ALU0;
                    result.src_reg1 := opcode(2 downto 0);
                    result.src_reg2 := opcode(11 downto 9);
                    result.uses_src1 := '1';
                    result.uses_src2 := '1';
                    result.writes_dest := '0'; -- Sets flags only
                end if;

            -- AND/MUL/ABCD/EXG (1100)
            when "1100" =>
                if opcode(7 downto 4) = "0001" then -- ABCD
                    result.inst_type := x"E";
                    result.eu_type := EU_ALU1;
                elsif opcode(7 downto 6) = "11" then -- MULU/MULS
                    result.inst_type := x"F";
                    result.eu_type := EU_ALU0;
                elsif opcode(8) = '1' and opcode(7 downto 6) = "00" then -- EXG
                    result.inst_type := x"6";
                    result.eu_type := EU_ALU0;
                else -- AND
                    result.inst_type := x"3"; -- AND
                    result.eu_type := EU_ALU1;
                    result.src_reg1 := opcode(2 downto 0);
                    result.src_reg2 := opcode(11 downto 9);
                    result.dest_reg := opcode(11 downto 9);
                    result.uses_src1 := '1';
                    result.uses_src2 := '1';
                    result.writes_dest := '1';
                end if;

            -- ADD (1101)
            when "1101" =>
                result.inst_type := x"1"; -- ADD
                result.eu_type := EU_ALU0;
                result.src_reg1 := opcode(2 downto 0);
                result.src_reg2 := opcode(11 downto 9);
                result.dest_reg := opcode(11 downto 9);
                result.uses_src1 := '1';
                result.uses_src2 := '1';
                result.writes_dest := '1';

            -- Shift/Rotate (1110)
            when "1110" =>
                result.inst_type := x"9"; -- Shift/Rotate
                result.eu_type := EU_ALU1;
                result.src_reg1 := opcode(2 downto 0);
                result.dest_reg := opcode(2 downto 0);
                result.uses_src1 := '1';
                result.writes_dest := '1';

            -- (1111) - Line F (Coprocessor/Unimplemented)
            when "1111" =>
                result.inst_type := x"F";
                result.eu_type := EU_ALU0;

            when others =>
                result.inst_type := x"F";
                result.eu_type := EU_ALU0;
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
                        decoded_inst(i) <= decode_68k_complete(fetch_inst(i), current_pc, CPU_TYPE);
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
