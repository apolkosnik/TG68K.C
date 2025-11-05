------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K Branch Predictor (2-Level Adaptive)                               --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- 2-level adaptive branch predictor with pattern history table            --
-- Predicts branch direction to reduce pipeline flushes                    --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_BranchPredictor is
    generic(
        BHT_SIZE : integer := 256;   -- Branch History Table size
        PHT_SIZE : integer := 1024   -- Pattern History Table size
    );
    port(
        clk             : in std_logic;
        reset           : in std_logic;
        enable          : in std_logic;

        -- Prediction request (from fetch/decode)
        predict_pc      : in std_logic_vector(31 downto 0);
        predict_req     : in std_logic;
        predict_taken   : out std_logic;
        predict_target  : out std_logic_vector(31 downto 0);

        -- Branch resolution (from execute/commit)
        resolve_pc      : in std_logic_vector(31 downto 0);
        resolve_valid   : in std_logic;
        resolve_taken   : in std_logic;
        resolve_target  : in std_logic_vector(31 downto 0);
        resolve_mispredict : out std_logic
    );
end TG68K_BranchPredictor;

architecture rtl of TG68K_BranchPredictor is

    -- Branch History Table (BHT) - stores local history per branch
    type bht_entry_t is record
        valid    : std_logic;
        history  : std_logic_vector(9 downto 0);  -- 10-bit history
        target   : std_logic_vector(31 downto 0);
    end record;

    type bht_t is array (0 to BHT_SIZE-1) of bht_entry_t;
    signal bht : bht_t;

    -- Pattern History Table (PHT) - 2-bit saturating counters
    type pht_t is array (0 to PHT_SIZE-1) of std_logic_vector(1 downto 0);
    signal pht : pht_t;

    -- Global history register
    signal global_history : std_logic_vector(9 downto 0);

    -- Helper function to hash PC for BHT index
    function hash_bht(pc : std_logic_vector(31 downto 0)) return integer is
    begin
        return to_integer(unsigned(pc(9 downto 2)));  -- Use bits [9:2] for 256 entries
    end function;

    -- Helper function to hash for PHT index (XOR with global history)
    function hash_pht(pc : std_logic_vector(31 downto 0); history : std_logic_vector(9 downto 0)) return integer is
        variable pc_bits : std_logic_vector(9 downto 0);
    begin
        pc_bits := pc(11 downto 2);
        return to_integer(unsigned(pc_bits xor history));
    end function;

    -- 2-bit saturating counter update
    function update_counter(counter : std_logic_vector(1 downto 0); taken : std_logic) return std_logic_vector is
    begin
        if taken = '1' then
            case counter is
                when "00" => return "01";  -- Strongly not taken -> Weakly not taken
                when "01" => return "10";  -- Weakly not taken -> Weakly taken
                when "10" => return "11";  -- Weakly taken -> Strongly taken
                when "11" => return "11";  -- Strongly taken -> Strongly taken
                when others => return "10";
            end case;
        else
            case counter is
                when "00" => return "00";  -- Strongly not taken -> Strongly not taken
                when "01" => return "00";  -- Weakly not taken -> Strongly not taken
                when "10" => return "01";  -- Weakly taken -> Weakly not taken
                when "11" => return "10";  -- Strongly taken -> Weakly taken
                when others => return "01";
            end case;
        end if;
    end function;

begin

    -- Prediction logic (combinational)
    process(predict_pc, predict_req, bht, pht, global_history)
        variable bht_idx : integer;
        variable pht_idx : integer;
        variable local_history : std_logic_vector(9 downto 0);
        variable counter : std_logic_vector(1 downto 0);
    begin
        predict_taken <= '0';
        predict_target <= (others => '0');

        if predict_req = '1' then
            bht_idx := hash_bht(predict_pc);

            if bht(bht_idx).valid = '1' then
                -- Use local history from BHT
                local_history := bht(bht_idx).history;
                predict_target <= bht(bht_idx).target;
            else
                -- Use global history if no local history
                local_history := global_history;
                predict_target <= (others => '0');
            end if;

            -- Look up PHT
            pht_idx := hash_pht(predict_pc, local_history);
            counter := pht(pht_idx);

            -- Predict taken if counter >= 2 (weakly taken or strongly taken)
            if counter(1) = '1' then
                predict_taken <= '1';
            else
                predict_taken <= '0';
            end if;
        end if;
    end process;

    -- Update logic (sequential)
    process(clk, reset)
        variable bht_idx : integer;
        variable pht_idx : integer;
        variable local_history : std_logic_vector(9 downto 0);
        variable counter : std_logic_vector(1 downto 0);
        variable predicted_taken : std_logic;
    begin
        if reset = '1' then
            -- Initialize BHT
            for i in 0 to BHT_SIZE-1 loop
                bht(i).valid <= '0';
                bht(i).history <= (others => '0');
                bht(i).target <= (others => '0');
            end loop;

            -- Initialize PHT to weakly taken (10)
            for i in 0 to PHT_SIZE-1 loop
                pht(i) <= "10";
            end loop;

            global_history <= (others => '0');
            resolve_mispredict <= '0';

        elsif rising_edge(clk) then
            if enable = '1' then

                resolve_mispredict <= '0';

                if resolve_valid = '1' then
                    bht_idx := hash_bht(resolve_pc);

                    -- Update BHT
                    if bht(bht_idx).valid = '1' then
                        local_history := bht(bht_idx).history;
                    else
                        bht(bht_idx).valid <= '1';
                        local_history := global_history;
                    end if;

                    -- Update target
                    if resolve_taken = '1' then
                        bht(bht_idx).target <= resolve_target;
                    end if;

                    -- Update local history (shift in taken bit)
                    bht(bht_idx).history <= local_history(8 downto 0) & resolve_taken;

                    -- Update PHT
                    pht_idx := hash_pht(resolve_pc, local_history);
                    counter := pht(pht_idx);
                    pht(pht_idx) <= update_counter(counter, resolve_taken);

                    -- Update global history
                    global_history <= global_history(8 downto 0) & resolve_taken;

                    -- Check for misprediction
                    predicted_taken := counter(1);
                    if predicted_taken /= resolve_taken then
                        resolve_mispredict <= '1';
                    end if;
                end if;

            end if;
        end if;
    end process;

end rtl;
