------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K SuperScalar Instruction Fetch Unit (4-wide)                       --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Fetches up to 4 instructions per cycle for superscalar execution        --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_InstructionFetch is
    port(
        clk             : in std_logic;
        reset           : in std_logic;
        enable          : in std_logic;

        -- PC management
        pc_in           : in std_logic_vector(31 downto 0);     -- Current PC
        pc_update       : in std_logic;                          -- Update PC (branch/exception)
        pc_new          : in std_logic_vector(31 downto 0);     -- New PC value

        -- Fetch control
        fetch_stall     : in std_logic;                          -- Stall fetch (ROB/RS full)
        flush_pipeline  : in std_logic;                          -- Flush on branch mispredict

        -- Memory interface (fetches 64 bits = 4 words at once)
        mem_addr        : out std_logic_vector(31 downto 0);    -- Memory address
        mem_read        : out std_logic;                         -- Memory read request
        mem_data        : in std_logic_vector(63 downto 0);     -- 4 instructions (64 bits)
        mem_ready       : in std_logic;                          -- Memory data ready

        -- Output: Fetched instructions
        fetch_valid     : out std_logic_vector(ISSUE_WIDTH-1 downto 0);  -- Valid flags
        fetch_pc        : out std_logic_vector(31 downto 0);    -- PC of first instruction
        fetch_inst      : out fetch_buffer_t                     -- 4 fetched instructions
    );
end TG68K_InstructionFetch;

architecture rtl of TG68K_InstructionFetch is

    signal pc_reg           : std_logic_vector(31 downto 0);
    signal fetch_buffer     : fetch_buffer_t;
    signal buffer_valid     : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal fetching         : std_logic;
    signal fetch_count      : integer range 0 to ISSUE_WIDTH;

begin

    -- Memory interface
    mem_addr <= pc_reg;
    mem_read <= enable and not fetch_stall and not fetching;

    process(clk, reset)
    begin
        if reset = '1' then
            pc_reg <= (others => '0');
            fetch_buffer <= (others => (others => '0'));
            buffer_valid <= (others => '0');
            fetching <= '0';
            fetch_count <= 0;

        elsif rising_edge(clk) then

            -- Handle pipeline flush
            if flush_pipeline = '1' then
                buffer_valid <= (others => '0');
                fetching <= '0';
                fetch_count <= 0;

            -- Handle PC update (branches, exceptions)
            elsif pc_update = '1' then
                pc_reg <= pc_new;
                buffer_valid <= (others => '0');
                fetching <= '0';
                fetch_count <= 0;

            elsif enable = '1' then

                -- Start new fetch
                if mem_read = '1' and mem_ready = '0' then
                    fetching <= '1';
                end if;

                -- Complete fetch
                if fetching = '1' and mem_ready = '1' then
                    -- Store 4 instructions from memory (64 bits = 4 x 16-bit words)
                    -- Assuming big-endian byte order for 68K
                    fetch_buffer(0) <= mem_data(63 downto 48);  -- First instruction
                    fetch_buffer(1) <= mem_data(47 downto 32);  -- Second instruction
                    fetch_buffer(2) <= mem_data(31 downto 16);  -- Third instruction
                    fetch_buffer(3) <= mem_data(15 downto 0);   -- Fourth instruction

                    -- Mark all 4 instructions as valid
                    buffer_valid <= (others => '1');
                    fetch_count <= ISSUE_WIDTH;
                    fetching <= '0';

                    -- Increment PC by 8 bytes (4 instructions)
                    if fetch_stall = '0' then
                        pc_reg <= std_logic_vector(unsigned(pc_reg) + 8);
                    end if;

                -- Instructions consumed by decode stage
                elsif fetch_stall = '0' and buffer_valid /= "0000" then
                    -- Clear consumed instructions
                    buffer_valid <= (others => '0');
                    fetch_count <= 0;
                end if;

            end if;
        end if;
    end process;

    -- Output assignments
    fetch_valid <= buffer_valid;
    fetch_inst <= fetch_buffer;
    fetch_pc <= pc_reg;

end rtl;
