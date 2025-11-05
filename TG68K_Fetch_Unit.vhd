--------------------------------------------------------------------------------
-- TG68K Superscalar Instruction Fetch Unit
-- Fetches up to 8 instructions per cycle with branch prediction
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Superscalar_Pack.all;

entity TG68K_Fetch_Unit is
    port (
        clk             : in std_logic;
        reset           : in std_logic;

        -- Fetch control
        fetch_enable    : in std_logic;                     -- Enable fetching
        stall           : in std_logic;                     -- Stall fetch (decode full)
        flush           : in std_logic;                     -- Flush on branch misprediction
        flush_pc        : in std_logic_vector(31 downto 0); -- PC to restore on flush

        -- Instruction cache interface
        icache_addr     : out std_logic_vector(31 downto 0);
        icache_req      : out std_logic;
        icache_data     : in std_logic_vector(255 downto 0); -- 16 words (8 instructions max)
        icache_valid    : in std_logic;

        -- Branch prediction interface
        bp_update       : in std_logic;                     -- Update predictor
        bp_update_pc    : in std_logic_vector(31 downto 0);
        bp_update_taken : in std_logic;
        bp_update_target: in std_logic_vector(31 downto 0);

        -- Output to decode stage (8-wide)
        fetch_instr     : out instruction_array_t;          -- Fetched instructions
        fetch_valid     : out std_logic_vector(ISSUE_WIDTH-1 downto 0); -- Valid bits
        fetch_pc        : out std_logic_vector(31 downto 0) -- Current fetch PC
    );
end entity TG68K_Fetch_Unit;

architecture rtl of TG68K_Fetch_Unit is

    -- Program counter
    signal pc_reg           : std_logic_vector(31 downto 0);
    signal pc_next          : std_logic_vector(31 downto 0);

    -- Instruction buffer (holds fetched cache line)
    signal instr_buffer     : std_logic_vector(255 downto 0);
    signal buffer_valid     : std_logic;
    signal buffer_pc        : std_logic_vector(31 downto 0);

    -- Branch prediction structures
    signal btb              : btb_array_t;
    signal bht              : bht_array_t;

    -- Fetch state
    type fetch_state_t is (FETCH_IDLE, FETCH_WAIT, FETCH_ACTIVE);
    signal fetch_state      : fetch_state_t;

    -- Predicted branch info
    signal predicted_branch : std_logic;
    signal predicted_target : std_logic_vector(31 downto 0);

begin

    -- =========================================================================
    -- Program Counter Management
    -- =========================================================================
    process(clk, reset)
    begin
        if reset = '1' then
            pc_reg <= (others => '0');
            fetch_state <= FETCH_IDLE;
            buffer_valid <= '0';

        elsif rising_edge(clk) then
            -- Handle flush (branch misprediction)
            if flush = '1' then
                pc_reg <= flush_pc;
                fetch_state <= FETCH_IDLE;
                buffer_valid <= '0';

            elsif stall = '0' and fetch_enable = '1' then
                -- Update PC
                if predicted_branch = '1' then
                    pc_reg <= predicted_target;     -- Branch predicted taken
                else
                    pc_reg <= pc_next;              -- Sequential fetch
                end if;

                -- State machine
                case fetch_state is
                    when FETCH_IDLE =>
                        if icache_valid = '1' then
                            instr_buffer <= icache_data;
                            buffer_pc <= pc_reg;
                            buffer_valid <= '1';
                            fetch_state <= FETCH_ACTIVE;
                        else
                            fetch_state <= FETCH_WAIT;
                        end if;

                    when FETCH_WAIT =>
                        if icache_valid = '1' then
                            instr_buffer <= icache_data;
                            buffer_pc <= pc_reg;
                            buffer_valid <= '1';
                            fetch_state <= FETCH_ACTIVE;
                        end if;

                    when FETCH_ACTIVE =>
                        -- Continue fetching
                        fetch_state <= FETCH_IDLE;
                        buffer_valid <= '0';
                end case;
            end if;
        end if;
    end process;

    -- Next PC calculation (sequential or branch)
    pc_next <= std_logic_vector(unsigned(pc_reg) + to_unsigned(16, 32)); -- +16 bytes (8 words)

    -- I-cache request
    icache_addr <= pc_reg;
    icache_req <= '1' when (fetch_enable = '1' and stall = '0' and flush = '0') else '0';

    -- =========================================================================
    -- Branch Prediction
    -- =========================================================================
    process(clk, reset)
        variable btb_index  : integer range 0 to BTB_SIZE-1;
        variable bht_index  : integer range 0 to BHT_SIZE-1;
        variable btb_tag    : std_logic_vector(19 downto 0);
    begin
        if reset = '1' then
            -- Initialize BTB and BHT
            for i in 0 to BTB_SIZE-1 loop
                btb(i).valid <= '0';
                btb(i).tag <= (others => '0');
                btb(i).target <= (others => '0');
                btb(i).prediction <= "01";  -- Weakly not-taken
            end loop;

            for i in 0 to BHT_SIZE-1 loop
                bht(i).prediction <= "01";  -- Weakly not-taken
            end loop;

            predicted_branch <= '0';
            predicted_target <= (others => '0');

        elsif rising_edge(clk) then
            -- BTB/BHT indexing
            btb_index := to_integer(unsigned(pc_reg(10 downto 2)));
            bht_index := to_integer(unsigned(pc_reg(12 downto 2)));
            btb_tag := pc_reg(31 downto 12);

            -- Branch prediction lookup
            if btb(btb_index).valid = '1' and btb(btb_index).tag = btb_tag then
                -- BTB hit
                if btb(btb_index).prediction(1) = '1' then
                    predicted_branch <= '1';
                    predicted_target <= btb(btb_index).target;
                else
                    predicted_branch <= '0';
                    predicted_target <= (others => '0');
                end if;
            else
                -- BTB miss - predict not-taken
                predicted_branch <= '0';
                predicted_target <= (others => '0');
            end if;

            -- Branch predictor update (from execute stage)
            if bp_update = '1' then
                btb_index := to_integer(unsigned(bp_update_pc(10 downto 2)));
                bht_index := to_integer(unsigned(bp_update_pc(12 downto 2)));
                btb_tag := bp_update_pc(31 downto 12);

                -- Update BTB
                btb(btb_index).valid <= '1';
                btb(btb_index).tag <= btb_tag;
                btb(btb_index).target <= bp_update_target;

                -- Update 2-bit saturating counter
                if bp_update_taken = '1' then
                    -- Branch taken - increment (saturate at 11)
                    if btb(btb_index).prediction /= "11" then
                        btb(btb_index).prediction <=
                            std_logic_vector(unsigned(btb(btb_index).prediction) + 1);
                    end if;
                else
                    -- Branch not taken - decrement (saturate at 00)
                    if btb(btb_index).prediction /= "00" then
                        btb(btb_index).prediction <=
                            std_logic_vector(unsigned(btb(btb_index).prediction) - 1);
                    end if;
                end if;

                -- Update BHT
                if bp_update_taken = '1' then
                    if bht(bht_index).prediction /= "11" then
                        bht(bht_index).prediction <=
                            std_logic_vector(unsigned(bht(bht_index).prediction) + 1);
                    end if;
                else
                    if bht(bht_index).prediction /= "00" then
                        bht(bht_index).prediction <=
                            std_logic_vector(unsigned(bht(bht_index).prediction) - 1);
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Instruction Alignment and Output
    -- =========================================================================
    process(buffer_valid, instr_buffer, buffer_pc)
    begin
        if buffer_valid = '1' then
            -- Extract 8 instructions from buffer (each 16-bit word)
            -- Note: 68K instructions are variable length, so this is simplified
            -- A full implementation would need complex alignment logic
            for i in 0 to ISSUE_WIDTH-1 loop
                fetch_instr(i).valid <= '1';
                fetch_instr(i).pc <= std_logic_vector(unsigned(buffer_pc) + to_unsigned(i*2, 32));
                fetch_instr(i).opcode <= instr_buffer((i+1)*16-1 downto i*16);

                -- Initialize other fields (will be filled by decode)
                fetch_instr(i).operation <= OP_NOP;
                fetch_instr(i).exec_unit <= EXEC_NONE;
                fetch_instr(i).src1_valid <= '0';
                fetch_instr(i).src2_valid <= '0';
                fetch_instr(i).dest_valid <= '0';
                fetch_instr(i).imm_valid <= '0';
                fetch_instr(i).mem_read <= '0';
                fetch_instr(i).mem_write <= '0';
                fetch_instr(i).is_branch <= '0';
                fetch_instr(i).may_trap <= '0';
                fetch_instr(i).privilege <= '0';

                fetch_valid(i) <= '1';
            end loop;
            fetch_pc <= buffer_pc;
        else
            -- No valid instructions
            for i in 0 to ISSUE_WIDTH-1 loop
                fetch_instr(i).valid <= '0';
                fetch_valid(i) <= '0';
            end loop;
            fetch_pc <= (others => '0');
        end if;
    end process;

end architecture rtl;
