------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K SuperScalar Testbench                                             --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Basic testbench for superscalar core                                    --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_SuperScalar_tb is
end TG68K_SuperScalar_tb;

architecture behavioral of TG68K_SuperScalar_tb is

    component TG68K_SuperScalar_Core is
        generic(
            SR_Read : integer := 2;
            VBR_Stackframe : integer := 2;
            extAddr_Mode : integer := 2;
            MUL_Mode : integer := 2;
            DIV_Mode : integer := 2;
            BitField : integer := 2;
            BarrelShifter : integer := 1;
            MUL_Hardware : integer := 1
        );
        port(
            clk : in std_logic; nReset : in std_logic; clkena_in : in std_logic;
            data_in : in std_logic_vector(15 downto 0);
            IPL : in std_logic_vector(2 downto 0);
            IPL_autovector : in std_logic; berr : in std_logic;
            CPU : in std_logic_vector(1 downto 0);
            addr_out : out std_logic_vector(31 downto 0);
            data_write : out std_logic_vector(15 downto 0);
            nWr : out std_logic; nUDS : out std_logic; nLDS : out std_logic;
            busstate : out std_logic_vector(1 downto 0);
            longword : out std_logic; nResetOut : out std_logic;
            FC : out std_logic_vector(2 downto 0);
            clr_berr : out std_logic; skipFetch : out std_logic;
            regin_out : out std_logic_vector(31 downto 0);
            CACR_out : out std_logic_vector(3 downto 0);
            VBR_out : out std_logic_vector(31 downto 0)
        );
    end component;

    -- Testbench signals
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal clkena : std_logic := '1';

    signal data_in : std_logic_vector(15 downto 0);
    signal addr_out : std_logic_vector(31 downto 0);
    signal data_write : std_logic_vector(15 downto 0);
    signal nWr, nUDS, nLDS : std_logic;
    signal busstate : std_logic_vector(1 downto 0);

    -- Simple memory
    type memory_t is array (0 to 4095) of std_logic_vector(15 downto 0);
    signal memory : memory_t := (others => x"0000");

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

    -- Simulation control
    signal sim_done : boolean := false;

begin

    -- Clock generation
    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- DUT instantiation
    dut : TG68K_SuperScalar_Core
        generic map(
            SR_Read => 2,
            VBR_Stackframe => 2,
            extAddr_Mode => 2,
            MUL_Mode => 2,
            DIV_Mode => 2,
            BitField => 2,
            BarrelShifter => 1,
            MUL_Hardware => 1
        )
        port map(
            clk => clk,
            nReset => reset_n,
            clkena_in => clkena,
            data_in => data_in,
            IPL => "111",
            IPL_autovector => '0',
            berr => '0',
            CPU => "01",  -- 68010
            addr_out => addr_out,
            data_write => data_write,
            nWr => nWr,
            nUDS => nUDS,
            nLDS => nLDS,
            busstate => busstate,
            longword => open,
            nResetOut => open,
            FC => open,
            clr_berr => open,
            skipFetch => open,
            regin_out => open,
            CACR_out => open,
            VBR_out => open
        );

    -- Memory simulation (simple)
    memory_proc : process(clk)
        variable addr_idx : integer;
    begin
        if rising_edge(clk) then
            addr_idx := to_integer(unsigned(addr_out(12 downto 1)));
            if addr_idx < 4096 then
                data_in <= memory(addr_idx);

                if nWr = '0' then
                    memory(addr_idx) <= data_write;
                end if;
            else
                data_in <= x"0000";
            end if;
        end if;
    end process;

    -- Test stimulus
    stimulus : process
    begin
        -- Initialize memory with test program
        -- Simple test: MOVEQ #5, D0; MOVEQ #10, D1; ADD.L D0, D1
        memory(0) <= x"7005";  -- MOVEQ #5, D0
        memory(1) <= x"720A";  -- MOVEQ #10, D1
        memory(2) <= x"D280";  -- ADD.L D0, D1
        memory(3) <= x"7210";  -- MOVEQ #16, D1
        memory(4) <= x"4E71";  -- NOP
        memory(5) <= x"4E71";  -- NOP

        -- Reset sequence
        reset_n <= '0';
        wait for 100 ns;
        reset_n <= '1';

        report "Starting superscalar test...";

        -- Run for a while
        wait for 1 us;

        report "Test completed";
        sim_done <= true;
        wait;
    end process;

    -- Monitor
    monitor : process(clk)
    begin
        if rising_edge(clk) then
            if busstate /= "01" then  -- Not idle
                report "Cycle: addr=" & to_hstring(addr_out) &
                       " data_in=" & to_hstring(data_in) &
                       " data_out=" & to_hstring(data_write) &
                       " state=" & to_string(busstate);
            end if;
        end if;
    end process;

end behavioral;
