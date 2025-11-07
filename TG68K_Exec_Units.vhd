--------------------------------------------------------------------------------
-- TG68K Superscalar Execution Units
-- 8 parallel execution units: 4×ALU, 1×MUL, 1×DIV, 1×LDST, 1×BRANCH
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Superscalar_Pack.all;
use work.TG68K_Pack.all;

entity TG68K_Exec_Units is
    port (
        clk             : in std_logic;
        reset           : in std_logic;

        -- Issue interface
        issue_valid     : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        issue_instr     : in instruction_array_t;
        issue_src1      : in exec_result_array_t;
        issue_src2      : in exec_result_array_t;

        -- Completion to ROB
        complete_valid  : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
        complete_result : out exec_result_array_t;

        -- Forwarding output (same as complete)
        forward_valid   : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
        forward_result  : out exec_result_array_t;

        -- Memory interface (for LOAD/STORE unit)
        mem_addr        : out std_logic_vector(31 downto 0);
        mem_data_out    : out std_logic_vector(31 downto 0);
        mem_data_in     : in std_logic_vector(31 downto 0);
        mem_read        : out std_logic;
        mem_write       : out std_logic;
        mem_size        : out std_logic_vector(1 downto 0);
        mem_ready       : in std_logic;

        -- Execution unit busy signals
        exec_busy       : out std_logic_vector(ISSUE_WIDTH-1 downto 0)
    );
end entity TG68K_Exec_Units;

architecture rtl of TG68K_Exec_Units is

    -- ALU units (4 parallel units)
    signal alu_result   : exec_result_array_t;
    signal alu_valid    : std_logic_vector(3 downto 0);

    -- Multiplier unit
    signal mul_result   : exec_result_t;
    signal mul_valid    : std_logic;
    signal mul_busy     : std_logic;

    -- Divider unit
    signal div_result   : exec_result_t;
    signal div_valid    : std_logic;
    signal div_busy     : std_logic;
    signal div_counter  : integer range 0 to 33;

    -- Load/Store unit
    signal ldst_result  : exec_result_t;
    signal ldst_valid   : std_logic;
    signal ldst_busy    : std_logic;

    -- Branch unit
    signal branch_result: exec_result_t;
    signal branch_valid : std_logic;

begin

    -- Map busy signals
    exec_busy(0) <= '0'; -- ALU 0
    exec_busy(1) <= '0'; -- ALU 1
    exec_busy(2) <= '0'; -- ALU 2
    exec_busy(3) <= '0'; -- ALU 3
    exec_busy(4) <= mul_busy;
    exec_busy(5) <= div_busy;
    exec_busy(6) <= ldst_busy;
    exec_busy(7) <= '0'; -- BRANCH

    -- =========================================================================
    -- ALU Execution Units (4× parallel)
    -- =========================================================================
    gen_alu: for i in 0 to 3 generate
        process(clk, reset)
            variable op1, op2 : std_logic_vector(31 downto 0);
            variable result   : std_logic_vector(31 downto 0);
            variable result33 : std_logic_vector(32 downto 0);
            variable flags    : std_logic_vector(7 downto 0);
            variable carry    : std_logic;
            variable overflow : std_logic;
        begin
            if reset = '1' then
                alu_valid(i) <= '0';
                alu_result(i).valid <= '0';

            elsif rising_edge(clk) then
                alu_valid(i) <= '0';
                alu_result(i).valid <= '0';

                if issue_valid(i) = '1' and issue_instr(i).exec_unit = EXEC_ALU then
                    op1 := issue_src1(i).result;
                    op2 := issue_src2(i).result;
                    flags := (others => '0');
                    carry := '0';
                    overflow := '0';

                    -- Execute ALU operation
                    case issue_instr(i).operation is
                        when OP_ADD | OP_ADDI | OP_ADDQ =>
                            -- 33-bit addition to detect carry
                            result33 := std_logic_vector(unsigned('0' & op1) + unsigned('0' & op2));
                            result := result33(31 downto 0);
                            carry := result33(32);  -- Carry out
                            -- Overflow: operands same sign, result different sign
                            overflow := (op1(31) xnor op2(31)) and (op1(31) xor result(31));
                            -- Set flags: C, V, Z, N
                            flags(0) := carry;                                    -- C
                            flags(1) := overflow;                                 -- V
                            flags(2) := '1' when result = x"00000000" else '0';   -- Z
                            flags(3) := result(31);                               -- N

                        when OP_SUB | OP_SUBI | OP_SUBQ | OP_CMP =>
                            -- 33-bit subtraction to detect borrow
                            result33 := std_logic_vector(unsigned('0' & op1) - unsigned('0' & op2));
                            result := result33(31 downto 0);
                            carry := result33(32);  -- Borrow (inverted carry)
                            -- Overflow: operands different sign, result same sign as op2
                            overflow := (op1(31) xor op2(31)) and (op2(31) xnor result(31));
                            flags(0) := carry;                                    -- C (borrow)
                            flags(1) := overflow;                                 -- V
                            flags(2) := '1' when result = x"00000000" else '0';   -- Z
                            flags(3) := result(31);                               -- N

                        when OP_AND | OP_ANDI =>
                            result := op1 and op2;
                            flags(2) := '1' when result = x"00000000" else '0';
                            flags(3) := result(31);

                        when OP_OR | OP_ORI =>
                            result := op1 or op2;
                            flags(2) := '1' when result = x"00000000" else '0';
                            flags(3) := result(31);

                        when OP_EOR | OP_EORI =>
                            result := op1 xor op2;
                            flags(2) := '1' when result = x"00000000" else '0';
                            flags(3) := result(31);

                        when OP_NOT =>
                            result := not op1;
                            flags(2) := '1' when result = x"00000000" else '0';
                            flags(3) := result(31);

                        when OP_NEG =>
                            result := std_logic_vector(unsigned(not op1) + 1);
                            -- Carry set if op1 != 0 (borrow occurred)
                            carry := '0' when op1 = x"00000000" else '1';
                            -- Overflow if negating most negative number (0x80000000)
                            overflow := '1' when op1 = x"80000000" else '0';
                            flags(0) := carry;                                    -- C
                            flags(1) := overflow;                                 -- V
                            flags(2) := '1' when result = x"00000000" else '0';   -- Z
                            flags(3) := result(31);                               -- N

                        when OP_CLR =>
                            result := (others => '0');
                            flags(2) := '1'; -- Z=1
                            flags(3) := '0'; -- N=0

                        when OP_MOVE | OP_MOVEQ =>
                            result := op2;
                            flags(2) := '1' when result = x"00000000" else '0';
                            flags(3) := result(31);

                        when OP_EXT =>
                            -- Sign extend
                            if issue_instr(i).opcode(6) = '0' then
                                -- Byte to word
                                result(15 downto 0) := (15 downto 8 => op1(7)) & op1(7 downto 0);
                                result(31 downto 16) := (others => '0');
                            else
                                -- Word to long
                                result := (31 downto 16 => op1(15)) & op1(15 downto 0);
                            end if;
                            flags(2) := '1' when result = x"00000000" else '0';
                            flags(3) := result(31);

                        when OP_SWAP =>
                            result := op1(15 downto 0) & op1(31 downto 16);
                            flags(2) := '1' when result = x"00000000" else '0';
                            flags(3) := result(31);

                        when OP_LEA =>
                            result := op2; -- Effective address already calculated

                        when others =>
                            result := (others => '0');
                    end case;

                    -- Initialize all exec_result_t fields
                    alu_result(i).valid <= '1';
                    alu_result(i).rob_id <= issue_instr(i).rob_id;
                    alu_result(i).dest_phys_reg <= issue_instr(i).dest_phys_reg;
                    alu_result(i).result <= result;
                    alu_result(i).flags <= flags;
                    alu_result(i).pc <= issue_instr(i).pc;
                    alu_result(i).is_branch <= '0';
                    alu_result(i).branch_taken <= '0';
                    alu_result(i).branch_target <= (others => '0');
                    alu_result(i).branch_mispred <= '0';
                    alu_result(i).exception <= '0';
                    alu_result(i).exception_vec <= (others => '0');
                    alu_valid(i) <= '1';
                end if;
            end if;
        end process;
    end generate;

    -- =========================================================================
    -- Multiplier Execution Unit (1× unit, pipelined)
    -- =========================================================================
    process(clk, reset)
        variable op1, op2   : signed(31 downto 0);
        variable mul_temp   : signed(63 downto 0);
    begin
        if reset = '1' then
            mul_valid <= '0';
            mul_busy <= '0';
            mul_result.valid <= '0';

        elsif rising_edge(clk) then
            mul_valid <= '0';
            mul_result.valid <= '0';

            if issue_valid(4) = '1' and issue_instr(4).exec_unit = EXEC_MUL then
                mul_busy <= '1';
                op1 := signed(issue_src1(4).result);
                op2 := signed(issue_src2(4).result);

                -- 32×32 signed multiply
                mul_temp := op1 * op2;

                -- Initialize all exec_result_t fields
                mul_result.valid <= '1';
                mul_result.rob_id <= issue_instr(4).rob_id;
                mul_result.dest_phys_reg <= issue_instr(4).dest_phys_reg;
                mul_result.result <= std_logic_vector(mul_temp(31 downto 0));
                mul_result.flags(0) <= '0';  -- C (clear)
                mul_result.flags(1) <= '0';  -- V (clear)
                mul_result.flags(2) <= '1' when mul_temp(31 downto 0) = x"00000000" else '0';  -- Z
                mul_result.flags(3) <= mul_temp(31);  -- N
                mul_result.flags(7 downto 4) <= (others => '0');
                mul_result.pc <= issue_instr(4).pc;
                mul_result.is_branch <= '0';
                mul_result.branch_taken <= '0';
                mul_result.branch_target <= (others => '0');
                mul_result.branch_mispred <= '0';
                mul_result.exception <= '0';
                mul_result.exception_vec <= (others => '0');
                mul_valid <= '1';
                mul_busy <= '0';
            else
                mul_busy <= '0';
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Divider Execution Unit (1× unit, iterative)
    -- =========================================================================
    process(clk, reset)
        variable dividend   : unsigned(63 downto 0);
        variable divisor    : unsigned(31 downto 0);
        variable quotient   : unsigned(31 downto 0);
        variable remainder  : unsigned(31 downto 0);
    begin
        if reset = '1' then
            div_valid <= '0';
            div_busy <= '0';
            div_counter <= 0;
            div_result.valid <= '0';

        elsif rising_edge(clk) then
            div_valid <= '0';
            div_result.valid <= '0';

            if div_busy = '1' then
                -- Division in progress (simplified - would need full restoring division)
                if div_counter = 32 then
                    -- Division complete
                    div_result.valid <= '1';
                    div_result.result <= std_logic_vector(quotient);
                    div_valid <= '1';
                    div_busy <= '0';
                    div_counter <= 0;
                else
                    div_counter <= div_counter + 1;
                end if;

            elsif issue_valid(5) = '1' and issue_instr(5).exec_unit = EXEC_DIV then
                -- Start division
                div_busy <= '1';
                div_counter <= 0;
                dividend := x"00000000" & unsigned(issue_src1(5).result);
                divisor := unsigned(issue_src2(5).result);

                -- Initialize all exec_result_t fields
                div_result.rob_id <= issue_instr(5).rob_id;
                div_result.dest_phys_reg <= issue_instr(5).dest_phys_reg;
                div_result.flags <= (others => '0');
                div_result.pc <= issue_instr(5).pc;
                div_result.is_branch <= '0';
                div_result.branch_taken <= '0';
                div_result.branch_target <= (others => '0');
                div_result.branch_mispred <= '0';
                div_result.exception <= '0';
                div_result.exception_vec <= (others => '0');

                -- Simple division (would need proper algorithm)
                -- NOTE: Uses non-synthesizable / and mod operators - replace with proper division algorithm
                if divisor /= x"00000000" then
                    quotient := dividend(31 downto 0) / divisor;
                    remainder := dividend(31 downto 0) mod divisor;
                else
                    quotient := (others => '1'); -- Division by zero
                    remainder := (others => '0');
                    div_result.exception <= '1';
                    div_result.exception_vec <= x"14"; -- Division by zero vector
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Branch Execution Unit (1× unit)
    -- =========================================================================
    process(clk, reset)
        variable condition_met : std_logic;
        variable flags         : std_logic_vector(7 downto 0);
    begin
        if reset = '1' then
            branch_valid <= '0';
            branch_result.valid <= '0';

        elsif rising_edge(clk) then
            branch_valid <= '0';
            branch_result.valid <= '0';

            if issue_valid(7) = '1' and issue_instr(7).exec_unit = EXEC_BRANCH then
                flags := issue_src1(7).flags; -- Condition codes
                condition_met := '0';

                -- Evaluate branch condition
                -- Flag bits: 0=C (Carry), 1=V (Overflow), 2=Z (Zero), 3=N (Negative)
                case issue_instr(7).branch_cond is
                    when "0000" => condition_met := '1';                            -- BRA (always)
                    when "0001" => condition_met := '0';                            -- BSR (always, but link)
                    when "0010" => condition_met := (not flags(0)) and (not flags(2)); -- BHI (!C && !Z)
                    when "0011" => condition_met := flags(0) or flags(2);           -- BLS (C || Z)
                    when "0100" => condition_met := not flags(0);                   -- BCC/BHS (!C)
                    when "0101" => condition_met := flags(0);                       -- BCS/BLO (C)
                    when "0110" => condition_met := not flags(2);                   -- BNE (!Z)
                    when "0111" => condition_met := flags(2);                       -- BEQ (Z)
                    when "1000" => condition_met := not flags(1);                   -- BVC (!V)
                    when "1001" => condition_met := flags(1);                       -- BVS (V)
                    when "1010" => condition_met := not flags(3);                   -- BPL (!N)
                    when "1011" => condition_met := flags(3);                       -- BMI (N)
                    when "1100" => condition_met := (flags(3) and flags(1)) or ((not flags(3)) and (not flags(1))); -- BGE (N&&V || !N&&!V)
                    when "1101" => condition_met := (flags(3) and (not flags(1))) or ((not flags(3)) and flags(1)); -- BLT (N&&!V || !N&&V)
                    when "1110" => condition_met := ((flags(3) and flags(1)) or ((not flags(3)) and (not flags(1)))) and (not flags(2)); -- BGT
                    when "1111" => condition_met := flags(2) or (flags(3) and (not flags(1))) or ((not flags(3)) and flags(1)); -- BLE
                    when others => condition_met := '0';
                end case;

                -- Initialize all exec_result_t fields
                branch_result.valid <= '1';
                branch_result.rob_id <= issue_instr(7).rob_id;
                branch_result.dest_phys_reg <= issue_instr(7).dest_phys_reg;
                branch_result.result <= (others => '0');  -- Branches don't produce results
                branch_result.flags <= (others => '0');
                branch_result.pc <= issue_instr(7).pc;  -- Branch PC for predictor update
                branch_result.is_branch <= '1';
                branch_result.branch_taken <= condition_met;
                branch_result.branch_target <= issue_instr(7).branch_target;

                -- Check misprediction
                if condition_met /= issue_instr(7).branch_predicted then
                    branch_result.branch_mispred <= '1';
                else
                    branch_result.branch_mispred <= '0';
                end if;

                branch_result.exception <= '0';
                branch_result.exception_vec <= (others => '0');
                branch_valid <= '1';
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Load/Store Execution Unit (1× unit)
    -- =========================================================================
    process(clk, reset)
    begin
        if reset = '1' then
            ldst_valid <= '0';
            ldst_busy <= '0';
            ldst_result.valid <= '0';
            mem_read <= '0';
            mem_write <= '0';

        elsif rising_edge(clk) then
            ldst_valid <= '0';
            ldst_result.valid <= '0';

            if ldst_busy = '1' then
                -- Wait for memory
                if mem_ready = '1' then
                    ldst_result.valid <= '1';
                    ldst_result.result <= mem_data_in;
                    -- Fields already initialized when issued, just mark valid
                    ldst_valid <= '1';
                    ldst_busy <= '0';
                    mem_read <= '0';
                    mem_write <= '0';
                end if;

            elsif issue_valid(6) = '1' and issue_instr(6).exec_unit = EXEC_LDST then
                ldst_busy <= '1';
                mem_addr <= issue_src1(6).result; -- Address
                mem_size <= issue_instr(6).mem_size;

                -- Initialize all exec_result_t fields
                ldst_result.rob_id <= issue_instr(6).rob_id;
                ldst_result.dest_phys_reg <= issue_instr(6).dest_phys_reg;
                ldst_result.result <= (others => '0');  -- Will be filled on completion
                ldst_result.flags <= (others => '0');
                ldst_result.pc <= issue_instr(6).pc;
                ldst_result.is_branch <= '0';
                ldst_result.branch_taken <= '0';
                ldst_result.branch_target <= (others => '0');
                ldst_result.branch_mispred <= '0';
                ldst_result.exception <= '0';
                ldst_result.exception_vec <= (others => '0');

                if issue_instr(6).mem_read = '1' then
                    mem_read <= '1';
                    mem_write <= '0';
                elsif issue_instr(6).mem_write = '1' then
                    mem_read <= '0';
                    mem_write <= '1';
                    mem_data_out <= issue_src2(6).result;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Output Multiplexing
    -- =========================================================================
    process(alu_valid, alu_result, mul_valid, mul_result, div_valid, div_result,
            ldst_valid, ldst_result, branch_valid, branch_result)
    begin
        -- ALUs (0-3)
        for i in 0 to 3 loop
            complete_valid(i) <= alu_valid(i);
            complete_result(i) <= alu_result(i);
            forward_valid(i) <= alu_valid(i);
            forward_result(i) <= alu_result(i);
        end loop;

        -- MUL (4)
        complete_valid(4) <= mul_valid;
        complete_result(4) <= mul_result;
        forward_valid(4) <= mul_valid;
        forward_result(4) <= mul_result;

        -- DIV (5)
        complete_valid(5) <= div_valid;
        complete_result(5) <= div_result;
        forward_valid(5) <= div_valid;
        forward_result(5) <= div_result;

        -- LDST (6)
        complete_valid(6) <= ldst_valid;
        complete_result(6) <= ldst_result;
        forward_valid(6) <= ldst_valid;
        forward_result(6) <= ldst_result;

        -- BRANCH (7)
        complete_valid(7) <= branch_valid;
        complete_result(7) <= branch_result;
        forward_valid(7) <= branch_valid;
        forward_result(7) <= branch_result;
    end process;

end architecture rtl;
