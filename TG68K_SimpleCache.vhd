------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K Simple Direct-Mapped Cache                                        --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Simple direct-mapped cache for instruction or data                      --
-- Configurable size and line width                                        --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity TG68K_SimpleCache is
    generic(
        CACHE_SIZE    : integer := 1024;  -- Total cache size in bytes
        LINE_SIZE     : integer := 16;     -- Cache line size in bytes
        ADDR_WIDTH    : integer := 32
    );
    port(
        clk           : in std_logic;
        reset         : in std_logic;
        enable        : in std_logic;

        -- CPU interface
        cpu_addr      : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        cpu_read      : in std_logic;
        cpu_write     : in std_logic;
        cpu_data_in   : in std_logic_vector(31 downto 0);
        cpu_data_out  : out std_logic_vector(31 downto 0);
        cpu_ready     : out std_logic;

        -- Memory interface
        mem_addr      : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        mem_read      : out std_logic;
        mem_write     : out std_logic;
        mem_data_in   : in std_logic_vector(31 downto 0);
        mem_data_out  : out std_logic_vector(31 downto 0);
        mem_ready     : in std_logic;

        -- Statistics
        cache_hits    : out std_logic_vector(31 downto 0);
        cache_misses  : out std_logic_vector(31 downto 0)
    );
end TG68K_SimpleCache;

architecture rtl of TG68K_SimpleCache is

    constant NUM_LINES : integer := CACHE_SIZE / LINE_SIZE;
    constant OFFSET_BITS : integer := 4;  -- log2(LINE_SIZE)
    constant INDEX_BITS : integer := 10;   -- log2(NUM_LINES)
    constant TAG_BITS : integer := ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;

    type cache_line_t is record
        valid : std_logic;
        dirty : std_logic;
        tag   : std_logic_vector(TAG_BITS-1 downto 0);
        data  : std_logic_vector(LINE_SIZE*8-1 downto 0);
    end record;

    type cache_t is array (0 to NUM_LINES-1) of cache_line_t;
    signal cache : cache_t;

    type state_t is (IDLE, READ_MISS, WRITE_MISS, WRITE_BACK);
    signal state : state_t;

    signal hit_count : unsigned(31 downto 0);
    signal miss_count : unsigned(31 downto 0);

    signal current_index : integer range 0 to NUM_LINES-1;
    signal current_tag : std_logic_vector(TAG_BITS-1 downto 0);
    signal current_offset : integer range 0 to LINE_SIZE-1;

begin

    cache_hits <= std_logic_vector(hit_count);
    cache_misses <= std_logic_vector(miss_count);

    process(clk, reset)
        variable index : integer;
        variable tag : std_logic_vector(TAG_BITS-1 downto 0);
        variable offset : integer;
        variable hit : std_logic;
    begin
        if reset = '1' then
            for i in 0 to NUM_LINES-1 loop
                cache(i).valid <= '0';
                cache(i).dirty <= '0';
            end loop;

            state <= IDLE;
            cpu_ready <= '0';
            mem_read <= '0';
            mem_write <= '0';
            hit_count <= (others => '0');
            miss_count <= (others => '0');

        elsif rising_edge(clk) then
            if enable = '1' then

                cpu_ready <= '0';
                mem_read <= '0';
                mem_write <= '0';

                -- Extract address fields
                tag := cpu_addr(ADDR_WIDTH-1 downto ADDR_WIDTH-TAG_BITS);
                index := to_integer(unsigned(cpu_addr(ADDR_WIDTH-TAG_BITS-1 downto OFFSET_BITS)));
                offset := to_integer(unsigned(cpu_addr(OFFSET_BITS-1 downto 0)));

                case state is
                    when IDLE =>
                        if cpu_read = '1' or cpu_write = '1' then
                            current_index <= index;
                            current_tag <= tag;
                            current_offset <= offset;

                            -- Check for hit
                            if cache(index).valid = '1' and cache(index).tag = tag then
                                hit := '1';
                                hit_count <= hit_count + 1;

                                if cpu_read = '1' then
                                    -- Read hit
                                    cpu_data_out <= cache(index).data(offset*8+31 downto offset*8);
                                    cpu_ready <= '1';
                                else
                                    -- Write hit
                                    cache(index).data(offset*8+31 downto offset*8) <= cpu_data_in;
                                    cache(index).dirty <= '1';
                                    cpu_ready <= '1';
                                end if;
                            else
                                -- Miss
                                hit := '0';
                                miss_count <= miss_count + 1;

                                if cpu_read = '1' then
                                    state <= READ_MISS;
                                else
                                    state <= WRITE_MISS;
                                end if;
                            end if;
                        end if;

                    when READ_MISS =>
                        -- Fetch line from memory
                        mem_addr <= cpu_addr;
                        mem_read <= '1';

                        if mem_ready = '1' then
                            cache(current_index).valid <= '1';
                            cache(current_index).tag <= current_tag;
                            cache(current_index).data(current_offset*8+31 downto current_offset*8) <= mem_data_in;
                            cpu_data_out <= mem_data_in;
                            cpu_ready <= '1';
                            state <= IDLE;
                        end if;

                    when WRITE_MISS =>
                        -- Write allocate
                        mem_addr <= cpu_addr;
                        mem_write <= '1';
                        mem_data_out <= cpu_data_in;

                        if mem_ready = '1' then
                            cache(current_index).valid <= '1';
                            cache(current_index).tag <= current_tag;
                            cache(current_index).data(current_offset*8+31 downto current_offset*8) <= cpu_data_in;
                            cache(current_index).dirty <= '1';
                            cpu_ready <= '1';
                            state <= IDLE;
                        end if;

                    when WRITE_BACK =>
                        -- Write back dirty line (not implemented in this simple version)
                        state <= IDLE;

                    when others =>
                        state <= IDLE;
                end case;

            end if;
        end if;
    end process;

end rtl;
