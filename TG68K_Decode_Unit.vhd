--------------------------------------------------------------------------------
-- TG68K Superscalar Instruction Decode Unit
-- Decodes up to 8 instructions in parallel
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Superscalar_Pack.all;
use work.TG68K_Pack.all;

entity TG68K_Decode_Unit is
    port (
        clk             : in std_logic;
        reset           : in std_logic;

        -- Input from fetch stage
        fetch_instr     : in instruction_array_t;
        fetch_valid     : in std_logic_vector(ISSUE_WIDTH-1 downto 0);

        -- Control
        stall           : in std_logic;
        flush           : in std_logic;

        -- Output to rename stage
        decode_instr    : out instruction_array_t;
        decode_valid    : out std_logic_vector(ISSUE_WIDTH-1 downto 0)
    );
end entity TG68K_Decode_Unit;

architecture rtl of TG68K_Decode_Unit is

    -- Decode one 68K instruction
    function decode_68k_instruction(
        opcode : std_logic_vector(15 downto 0);
        pc     : std_logic_vector(31 downto 0)
    ) return instruction_t is
        variable instr : instruction_t;
        variable op_type : integer;
        variable reg_src : integer;
        variable reg_dst : integer;
        variable ea_mode : std_logic_vector(2 downto 0);
        variable ea_reg  : std_logic_vector(2 downto 0);
    begin
        -- Initialize
        instr.valid := '1';
        instr.pc := pc;
        instr.opcode := opcode;
        instr.src1_valid := '0';
        instr.src2_valid := '0';
        instr.dest_valid := '0';
        instr.imm_valid := '0';
        instr.mem_read := '0';
        instr.mem_write := '0';
        instr.is_branch := '0';
        instr.may_trap := '0';
        instr.privilege := '0';

        -- Decode based on opcode pattern (simplified 68K decode)
        -- Bits 15-12: Primary opcode group
        case opcode(15 downto 12) is
            -- 0000: Bit manipulation, MOVEP, Immediate
            when "0000" =>
                if opcode(8) = '1' then
                    -- Bit manipulation (BTST, BCHG, BCLR, BSET)
                    instr.operation := OP_BTST;
                    instr.exec_unit := EXEC_ALU;
                    instr.src1_valid := '1';
                    instr.src1_arch_reg := to_integer(unsigned(opcode(11 downto 9))); -- Dn
                    instr.src2_valid := '1';
                    instr.src2_arch_reg := to_integer(unsigned(opcode(2 downto 0)));  -- EA
                else
                    -- Immediate operations (ORI, ANDI, SUBI, ADDI, etc.)
                    case opcode(11 downto 8) is
                        when "0000" => instr.operation := OP_ORI;
                        when "0010" => instr.operation := OP_ANDI;
                        when "0100" => instr.operation := OP_SUBI;
                        when "0110" => instr.operation := OP_ADDI;
                        when others => instr.operation := OP_INVALID;
                    end case;
                    instr.exec_unit := EXEC_ALU;
                    instr.src1_valid := '1';
                    instr.src1_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                    instr.dest_valid := '1';
                    instr.dest_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                    instr.imm_valid := '1';
                end if;

            -- 0001, 0010, 0011: MOVE
            when "0001" | "0010" | "0011" =>
                instr.operation := OP_MOVE;
                instr.exec_unit := EXEC_ALU;
                -- Source: bits 5-0 (mode + reg)
                instr.src1_valid := '1';
                instr.src1_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                -- Destination: bits 11-6
                instr.dest_valid := '1';
                instr.dest_arch_reg := to_integer(unsigned(opcode(11 downto 9))) + 8; -- Data reg

            -- 0100: Miscellaneous (LEA, CLR, NEG, NOT, EXT, MOVEM, JSR, JMP, etc.)
            when "0100" =>
                case opcode(11 downto 8) is
                    when "0000" =>
                        instr.operation := OP_NEG;
                        instr.exec_unit := EXEC_ALU;
                    when "0010" =>
                        instr.operation := OP_CLR;
                        instr.exec_unit := EXEC_ALU;
                    when "0100" =>
                        instr.operation := OP_NOT;
                        instr.exec_unit := EXEC_ALU;
                    when "1000" =>
                        instr.operation := OP_EXT;
                        instr.exec_unit := EXEC_ALU;
                    when "1100" | "1110" =>
                        -- MOVEM
                        instr.operation := OP_MOVEM;
                        instr.exec_unit := EXEC_LDST;
                    when "1101" | "1111" =>
                        -- LEA
                        instr.operation := OP_LEA;
                        instr.exec_unit := EXEC_ALU;
                    when others =>
                        -- JSR, JMP
                        if opcode(7 downto 6) = "10" then
                            instr.operation := OP_JSR;
                            instr.is_branch := '1';
                            instr.exec_unit := EXEC_BRANCH;
                        elsif opcode(7 downto 6) = "11" then
                            instr.operation := OP_JMP;
                            instr.is_branch := '1';
                            instr.exec_unit := EXEC_BRANCH;
                        else
                            instr.operation := OP_INVALID;
                            instr.exec_unit := EXEC_NONE;
                        end if;
                end case;

            -- 0101: ADDQ, SUBQ, Scc, DBcc
            when "0101" =>
                if opcode(7 downto 6) = "11" then
                    -- DBcc
                    instr.operation := OP_DBCC;
                    instr.is_branch := '1';
                    instr.exec_unit := EXEC_BRANCH;
                else
                    -- ADDQ or SUBQ
                    if opcode(8) = '0' then
                        instr.operation := OP_ADDQ;
                    else
                        instr.operation := OP_SUBQ;
                    end if;
                    instr.exec_unit := EXEC_ALU;
                    instr.src1_valid := '1';
                    instr.src1_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                    instr.dest_valid := '1';
                    instr.dest_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                    instr.imm_valid := '1';
                end if;

            -- 0110: Bcc, BSR, BRA
            when "0110" =>
                if opcode(11 downto 8) = "0000" then
                    instr.operation := OP_BRA;
                elsif opcode(11 downto 8) = "0001" then
                    instr.operation := OP_BSR;
                else
                    instr.operation := OP_BCC;
                end if;
                instr.is_branch := '1';
                instr.exec_unit := EXEC_BRANCH;
                instr.branch_cond := opcode(11 downto 8);

            -- 0111: MOVEQ
            when "0111" =>
                instr.operation := OP_MOVEQ;
                instr.exec_unit := EXEC_ALU;
                instr.dest_valid := '1';
                instr.dest_arch_reg := to_integer(unsigned(opcode(11 downto 9))); -- Dn
                instr.imm_valid := '1';

            -- 1000: OR, DIV, SBCD
            when "1000" =>
                if opcode(7 downto 4) = "0100" then
                    -- SBCD
                    instr.operation := OP_SBCD;
                    instr.exec_unit := EXEC_ALU;
                elsif opcode(8 downto 6) = "111" then
                    -- DIVS
                    instr.operation := OP_DIVS;
                    instr.exec_unit := EXEC_DIV;
                    instr.src1_valid := '1';
                    instr.src1_arch_reg := to_integer(unsigned(opcode(11 downto 9))); -- Dn
                    instr.src2_valid := '1';
                    instr.src2_arch_reg := to_integer(unsigned(opcode(2 downto 0)));  -- EA
                    instr.dest_valid := '1';
                    instr.dest_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                else
                    -- OR
                    instr.operation := OP_OR;
                    instr.exec_unit := EXEC_ALU;
                    instr.src1_valid := '1';
                    instr.src1_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                    instr.src2_valid := '1';
                    instr.src2_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                    instr.dest_valid := '1';
                    instr.dest_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                end if;

            -- 1001: SUB, SUBX
            when "1001" =>
                if opcode(7 downto 4) = "0100" then
                    -- SUBX
                    instr.operation := OP_SUBX;
                else
                    -- SUB or SUBA
                    if opcode(8 downto 6) = "011" or opcode(8 downto 6) = "111" then
                        instr.operation := OP_SUBA;
                    else
                        instr.operation := OP_SUB;
                    end if;
                end if;
                instr.exec_unit := EXEC_ALU;
                instr.src1_valid := '1';
                instr.src1_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                instr.src2_valid := '1';
                instr.src2_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                instr.dest_valid := '1';
                instr.dest_arch_reg := to_integer(unsigned(opcode(11 downto 9)));

            -- 1011: CMP, EOR
            when "1011" =>
                if opcode(8 downto 6) = "011" or opcode(8 downto 6) = "111" then
                    -- CMPA
                    instr.operation := OP_CMPA;
                elsif opcode(8) = '1' then
                    -- EOR
                    instr.operation := OP_EOR;
                    instr.dest_valid := '1';
                    instr.dest_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                else
                    -- CMP
                    instr.operation := OP_CMP;
                end if;
                instr.exec_unit := EXEC_ALU;
                instr.src1_valid := '1';
                instr.src1_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                instr.src2_valid := '1';
                instr.src2_arch_reg := to_integer(unsigned(opcode(2 downto 0)));

            -- 1100: AND, MUL, ABCD, EXG
            when "1100" =>
                if opcode(7 downto 4) = "0100" then
                    -- ABCD
                    instr.operation := OP_ABCD;
                    instr.exec_unit := EXEC_ALU;
                elsif opcode(8 downto 6) = "011" then
                    -- MULU
                    instr.operation := OP_MULU;
                    instr.exec_unit := EXEC_MUL;
                    instr.src1_valid := '1';
                    instr.src1_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                    instr.src2_valid := '1';
                    instr.src2_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                    instr.dest_valid := '1';
                    instr.dest_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                elsif opcode(8 downto 6) = "111" then
                    -- MULS
                    instr.operation := OP_MULS;
                    instr.exec_unit := EXEC_MUL;
                    instr.src1_valid := '1';
                    instr.src1_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                    instr.src2_valid := '1';
                    instr.src2_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                    instr.dest_valid := '1';
                    instr.dest_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                else
                    -- AND
                    instr.operation := OP_AND;
                    instr.exec_unit := EXEC_ALU;
                    instr.src1_valid := '1';
                    instr.src1_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                    instr.src2_valid := '1';
                    instr.src2_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                    instr.dest_valid := '1';
                    instr.dest_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                end if;

            -- 1101: ADD, ADDX
            when "1101" =>
                if opcode(7 downto 4) = "0100" then
                    -- ADDX
                    instr.operation := OP_ADDX;
                else
                    -- ADD or ADDA
                    if opcode(8 downto 6) = "011" or opcode(8 downto 6) = "111" then
                        instr.operation := OP_ADDA;
                    else
                        instr.operation := OP_ADD;
                    end if;
                end if;
                instr.exec_unit := EXEC_ALU;
                instr.src1_valid := '1';
                instr.src1_arch_reg := to_integer(unsigned(opcode(11 downto 9)));
                instr.src2_valid := '1';
                instr.src2_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                instr.dest_valid := '1';
                instr.dest_arch_reg := to_integer(unsigned(opcode(11 downto 9)));

            -- 1110: Shift/Rotate, Bit field (68020+)
            when "1110" =>
                if opcode(7 downto 6) = "11" then
                    -- Memory shifts
                    case opcode(10 downto 9) is
                        when "00" => instr.operation := OP_ASR;
                        when "01" => instr.operation := OP_ASL;
                        when "10" => instr.operation := OP_LSR;
                        when "11" => instr.operation := OP_LSL;
                        when others => instr.operation := OP_INVALID;
                    end case;
                    instr.exec_unit := EXEC_SHIFT;
                else
                    -- Register shifts
                    case opcode(4 downto 3) is
                        when "00" => instr.operation := OP_ASR;
                        when "01" => instr.operation := OP_LSR;
                        when "10" => instr.operation := OP_ROXR;
                        when "11" => instr.operation := OP_ROR;
                        when others => instr.operation := OP_INVALID;
                    end case;
                    instr.exec_unit := EXEC_SHIFT;
                    instr.src1_valid := '1';
                    instr.src1_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                    instr.dest_valid := '1';
                    instr.dest_arch_reg := to_integer(unsigned(opcode(2 downto 0)));
                end if;

            -- 1111: Coprocessor, 68020+ instructions
            when "1111" =>
                -- For now, mark as invalid (would need 68020+ decode)
                instr.operation := OP_INVALID;
                instr.exec_unit := EXEC_NONE;

            when others =>
                instr.operation := OP_INVALID;
                instr.exec_unit := EXEC_NONE;
        end case;

        return instr;
    end function;

begin

    -- =========================================================================
    -- Parallel Decode (8-way)
    -- =========================================================================
    process(clk, reset)
    begin
        if reset = '1' then
            for i in 0 to ISSUE_WIDTH-1 loop
                decode_instr(i).valid <= '0';
                decode_valid(i) <= '0';
            end loop;

        elsif rising_edge(clk) then
            if flush = '1' then
                -- Flush pipeline
                for i in 0 to ISSUE_WIDTH-1 loop
                    decode_instr(i).valid <= '0';
                    decode_valid(i) <= '0';
                end loop;

            elsif stall = '0' then
                -- Decode up to 8 instructions in parallel
                for i in 0 to ISSUE_WIDTH-1 loop
                    if fetch_valid(i) = '1' then
                        decode_instr(i) <= decode_68k_instruction(
                            fetch_instr(i).opcode,
                            fetch_instr(i).pc
                        );
                        decode_valid(i) <= '1';
                    else
                        decode_instr(i).valid <= '0';
                        decode_valid(i) <= '0';
                    end if;
                end loop;
            end if;
        end if;
    end process;

end architecture rtl;
