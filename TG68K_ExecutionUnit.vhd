------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K SuperScalar Execution Unit                                        --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Generic execution unit for ALU, LSU, or Branch operations               --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_ExecutionUnit is
    generic(
        EU_TYPE : integer := EU_ALU0  -- Execution unit type
    );
    port(
        clk             : in std_logic;
        reset           : in std_logic;
        enable          : in std_logic;

        -- Issue interface
        issue_valid     : in std_logic;
        issue_opcode    : in std_logic_vector(15 downto 0);
        issue_pc        : in std_logic_vector(31 downto 0);
        issue_rob_idx   : in integer range 0 to ROB_SIZE-1;
        issue_src1      : in std_logic_vector(31 downto 0);
        issue_src2      : in std_logic_vector(31 downto 0);
        issue_imm       : in std_logic_vector(31 downto 0);

        -- Execution status
        eu_busy         : out std_logic;

        -- Completion interface
        complete_valid  : out std_logic;
        complete_rob_idx: out integer range 0 to ROB_SIZE-1;
        complete_result : out std_logic_vector(31 downto 0);
        complete_exception : out std_logic;

        -- Memory interface (for LSU only)
        mem_addr        : out std_logic_vector(31 downto 0);
        mem_write       : out std_logic;
        mem_read        : out std_logic;
        mem_data_out    : out std_logic_vector(31 downto 0);
        mem_data_in     : in std_logic_vector(31 downto 0);
        mem_ready       : in std_logic
    );
end TG68K_ExecutionUnit;

architecture rtl of TG68K_ExecutionUnit is

    signal busy         : std_logic;
    signal cycles_left  : integer range 0 to 15;
    signal rob_idx_reg  : integer range 0 to ROB_SIZE-1;
    signal result_reg   : std_logic_vector(31 downto 0);
    signal opcode_reg   : std_logic_vector(15 downto 0);
    signal src1_reg     : std_logic_vector(31 downto 0);
    signal src2_reg     : std_logic_vector(31 downto 0);
    signal imm_reg      : std_logic_vector(31 downto 0);
    signal is_store     : std_logic;
    signal mem_pending  : std_logic;

begin

    eu_busy <= busy;

    process(clk, reset)
        variable alu_result : std_logic_vector(31 downto 0);
        variable inst_type : std_logic_vector(3 downto 0);
    begin
        if reset = '1' then
            busy <= '0';
            complete_valid <= '0';
            cycles_left <= 0;
            result_reg <= (others => '0');
            complete_exception <= '0';
            mem_write <= '0';
            mem_read <= '0';
            mem_addr <= (others => '0');
            mem_data_out <= (others => '0');
            is_store <= '0';
            mem_pending <= '0';

        elsif rising_edge(clk) then

            if enable = '1' then

                complete_valid <= '0';

                -- Accept new instruction
                if issue_valid = '1' and busy = '0' then
                    busy <= '1';
                    rob_idx_reg <= issue_rob_idx;
                    opcode_reg <= issue_opcode;
                    src1_reg <= issue_src1;
                    src2_reg <= issue_src2;
                    imm_reg <= issue_imm;

                    -- Determine execution latency and memory operation type
                    if EU_TYPE = EU_ALU0 or EU_TYPE = EU_ALU1 then
                        cycles_left <= 1;  -- 1 cycle for simple ALU ops
                    elsif EU_TYPE = EU_LSU then
                        cycles_left <= 2;  -- 2+ cycles for memory ops
                        -- Check opcode for load vs store (simplified)
                        is_store <= issue_opcode(8);  -- Bit 8 often indicates store in 68K
                        mem_pending <= '1';
                    elsif EU_TYPE = EU_BRANCH then
                        cycles_left <= 1;  -- 1 cycle for branches
                    else
                        cycles_left <= 1;
                    end if;

                -- Execute instruction
                elsif busy = '1' then

                    if cycles_left > 0 then
                        cycles_left <= cycles_left - 1;

                        -- Perform operation based on EU type
                        if EU_TYPE = EU_ALU0 or EU_TYPE = EU_ALU1 then
                            -- Simple ALU operations
                            inst_type := opcode_reg(15 downto 12);

                            case inst_type is
                                when x"1" | x"2" | x"3" =>  -- MOVE
                                    alu_result := src1_reg;

                                when x"D" =>  -- ADD
                                    alu_result := std_logic_vector(unsigned(src1_reg) + unsigned(src2_reg));

                                when x"9" =>  -- SUB
                                    alu_result := std_logic_vector(unsigned(src2_reg) - unsigned(src1_reg));

                                when x"C" =>  -- AND
                                    alu_result := src1_reg and src2_reg;

                                when x"8" =>  -- OR
                                    alu_result := src1_reg or src2_reg;

                                when x"B" =>  -- EOR
                                    alu_result := src1_reg xor src2_reg;

                                when x"7" =>  -- MOVEQ
                                    alu_result := imm_reg;

                                when others =>
                                    alu_result := (others => '0');
                            end case;

                            result_reg <= alu_result;

                        elsif EU_TYPE = EU_LSU then
                            -- Load/Store operations
                            -- Calculate effective address
                            result_reg <= std_logic_vector(unsigned(src1_reg) + unsigned(imm_reg));

                            -- Drive memory interface
                            if mem_pending = '1' then
                                mem_addr <= std_logic_vector(unsigned(src1_reg) + unsigned(imm_reg));
                                if is_store = '1' then
                                    mem_write <= '1';
                                    mem_read <= '0';
                                    mem_data_out <= src2_reg;  -- Store data from src2
                                else
                                    mem_write <= '0';
                                    mem_read <= '1';
                                    -- Wait for mem_ready, then capture data
                                    if mem_ready = '1' then
                                        result_reg <= mem_data_in;
                                        mem_pending <= '0';
                                        mem_read <= '0';
                                    end if;
                                end if;
                            end if;

                        elsif EU_TYPE = EU_BRANCH then
                            -- Branch operations
                            -- Simplified: compute target address
                            result_reg <= std_logic_vector(unsigned(src1_reg) + unsigned(imm_reg));
                        end if;

                    else
                        -- Execution complete
                        complete_valid <= '1';
                        complete_rob_idx <= rob_idx_reg;
                        complete_result <= result_reg;
                        complete_exception <= '0';
                        busy <= '0';
                        -- Clear memory interface
                        mem_write <= '0';
                        mem_read <= '0';
                        mem_pending <= '0';
                    end if;

                end if;

            end if;
        end if;
    end process;

end rtl;
