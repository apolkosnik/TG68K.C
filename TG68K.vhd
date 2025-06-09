------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- This is the TOP-Level for TG68K.C to generate 68K Bus signals            --
--                                                                          --
-- Copyright (c) 2021 Tobias Gubener <tobiflex@opencores.org>               -- 
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU Lesser General Public License as published --
-- by the Free Software Foundation, either version 3 of the License, or     --
-- (at your option) any later version.                                      --
--                                                                          --
-- This source file is distributed in the hope that it will be useful,      --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of           --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            --
-- GNU General Public License for more details.                             --
--                                                                          --
-- You should have received a copy of the GNU General Public License        --
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.    --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

-- TG68K: Top-level entity that wraps the TG68KdotC_Kernel core
-- and generates proper 68K bus signals with timing control
entity TG68K is
   generic(
      -- CPU type selection: "00"=68000, "01"=68010, "11"=68020
      CPU           : std_logic_vector(1 downto 0):="01"  -- Default: 68010
   );
   port(        
      -- Clock and Reset signals
      CLK           : in std_logic;                        -- System clock
      RESET         : inout std_logic;                     -- Bidirectional reset (can be driven by CPU)
      HALT          : inout std_logic;                     -- Bidirectional halt signal
      
      -- Exception and interrupt signals
      BERR          : in std_logic;                        -- Bus error input (68000 stack pointer dummy for Atari ST)
      IPL           : in std_logic_vector(2 downto 0):="111"; -- Interrupt priority level (active low, 111=no interrupt)
      
      -- Address and function code outputs
      ADDR          : out std_logic_vector(31 downto 0);  -- 32-bit address bus
      FC            : out std_logic_vector(2 downto 0);   -- Function codes (supervisor/user, program/data)
      
      -- Data bus (bidirectional)
      DATA          : inout std_logic_vector(15 downto 0); -- 16-bit data bus
      
---- Bus arbitration signals (commented out - not used in this implementation)
--      BG            : out std_logic;                    -- Bus grant
--      BR         	  : in std_logic:='1';                -- Bus request
--      BGACK         : in std_logic:='1';                -- Bus grant acknowledge
      
-- Asynchronous bus interface signals
      AS            : out std_logic;                       -- Address strobe (active low)
      UDS           : out std_logic;                       -- Upper data strobe (active low)
      LDS           : out std_logic;                       -- Lower data strobe (active low)
      RW            : out std_logic;                       -- Read/Write (1=read, 0=write)
      DTACK         : in std_logic;                        -- Data transfer acknowledge (active low)
      
-- Synchronous bus interface signals (for 6800-style peripherals)
      E             : out std_logic;                       -- Enable clock (6800 E-clock)
      VPA           : in std_logic;                        -- Valid peripheral address (active low)
      VMA           : out std_logic                        -- Valid memory address (active low)
   );
end TG68K;

ARCHITECTURE logic OF TG68K IS

-- Component declaration for the actual 68K processor core
COMPONENT TG68KdotC_Kernel 
   generic(
      SR_Read : integer:= 2;           --0=>user,     1=>privileged,    2=>switchable with CPU(0)
      VBR_Stackframe : integer:= 2;    --0=>no,       1=>yes/extended,  2=>switchable with CPU(0)
      extAddr_Mode : integer:= 2;      --0=>no,       1=>yes,           2=>switchable with CPU(1)
      MUL_Mode : integer := 2;         --0=>16Bit,    1=>32Bit,         2=>switchable with CPU(1),  3=>no MUL,  
      DIV_Mode : integer := 2;         --0=>16Bit,    1=>32Bit,         2=>switchable with CPU(1),  3=>no DIV,  
      BitField : integer := 2;         --0=>no,       1=>yes,           2=>switchable with CPU(1) 
      
      BarrelShifter : integer := 2;    --0=>no,       1=>yes,           2=>switchable with CPU(1)  
      MUL_Hardware : integer := 1      --0=>no,       1=>yes,  
   );
   port(
      CPU            : in std_logic_vector(1 downto 0):="01";  -- 00->68000  01->68010  11->68020
      clk            : in std_logic;
      nReset         : in std_logic:='1';    --low active
      clkena_in      : in std_logic:='1';
      data_in        : in std_logic_vector(15 downto 0);
      IPL            : in std_logic_vector(2 downto 0):="111";
      IPL_autovector : in std_logic:='0';
      addr_out       : out std_logic_vector(31 downto 0);
      berr           : in std_logic:='0';     -- only 68000 Stackpointer dummy for Atari ST core
      FC             : out std_logic_vector(2 downto 0);
      data_write     : out std_logic_vector(15 downto 0);
      busstate       : out std_logic_vector(1 downto 0);	
      nWr            : out std_logic;
      nUDS, nLDS     : out std_logic;
      nResetOut      : out std_logic;
      skipFetch      : out std_logic
--      longword       : out std_logic;
--      clr_berr       : out std_logic;
   );
   END COMPONENT;


   -- Internal signals for data handling
   SIGNAL data_write  : std_logic_vector(15 downto 0);    -- Data to be written by CPU
   SIGNAL r_data      : std_logic_vector(15 downto 0);    -- Data read from bus
   SIGNAL cpuIPL      : std_logic_vector(2 downto 0);     -- Latched interrupt priority level
   
   -- Bus control signals for synchronous state machine
   SIGNAL data_akt_s  : std_logic;                         -- Data active (sync rising edge)
   SIGNAL data_akt_e  : std_logic;                         -- Data active (sync falling edge)
   SIGNAL as_s        : std_logic;                         -- Address strobe (sync rising)
   SIGNAL as_e        : std_logic;                         -- Address strobe (sync falling)
   SIGNAL uds_s       : std_logic;                         -- Upper data strobe (sync rising)
   SIGNAL uds_e       : std_logic;                         -- Upper data strobe (sync falling)
   SIGNAL lds_s       : std_logic;                         -- Lower data strobe (sync rising)
   SIGNAL lds_e       : std_logic;                         -- Lower data strobe (sync falling)
   SIGNAL rw_s        : std_logic;                         -- Read/Write (sync rising)
   SIGNAL rw_e        : std_logic;                         -- Read/Write (sync falling)
   
   -- Synchronous peripheral interface signals
   SIGNAL vpad        : std_logic;                         -- Latched VPA signal
   SIGNAL waitm       : std_logic;                         -- Wait state (DTACK latched)
   SIGNAL clkena_e    : std_logic;                         -- Clock enable (falling edge)
   
   -- State machine signals
   SIGNAL S_state     : std_logic_vector(1 downto 0);     -- Main bus state machine
   SIGNAL decode      : std_logic;                         -- Decode state
   SIGNAL wr          : std_logic;                         -- Write signal from CPU core
   SIGNAL uds_in      : std_logic;                         -- UDS from CPU core
   SIGNAL lds_in      : std_logic;                         -- LDS from CPU core
   SIGNAL state       : std_logic_vector(1 downto 0);     -- Bus state from CPU core
   SIGNAL clkena      : std_logic;                         -- Clock enable to CPU core
   SIGNAL skipFetch   : std_logic;                         -- Skip fetch cycle flag
   SIGNAL nResetOut   : std_logic;                         -- Reset output from CPU core
   SIGNAL autovector  : std_logic;                         -- Autovector interrupt flag
   SIGNAL cpu1reset   : std_logic;                         -- Combined reset signal to CPU

   -- E-clock generation state machine (10-state synchronous clock)
   type sync_state_t is (sync0, sync1, sync2, sync3, sync4, sync5, sync6, sync7, sync8, sync9);
   signal sync_state : sync_state_t;

BEGIN  
   -- Data bus tristate control: only drive during write operations
   DATA <= data_write WHEN data_akt_e='1' OR data_akt_s='1' ELSE "ZZZZZZZZZZZZZZZZ";
   
   -- Combine rising and falling edge versions of control signals
   AS <= as_s AND as_e;        -- Both must be high for AS to be high (active low signal)
   RW <= rw_s AND rw_e;        -- Both must be high for read operation
   UDS <= uds_s AND uds_e;     -- Both must be high for UDS inactive
   LDS <= lds_s AND lds_e;     -- Both must be high for LDS inactive
   
   -- Open-drain RESET and HALT outputs (driven low by CPU, otherwise high-Z)
   RESET <= '0' WHEN nResetOut='0' ELSE 'Z';
   HALT <=  '0' WHEN nResetOut='0' ELSE 'Z';
   
   -- Combine external RESET/HALT with CPU-generated reset
   cpu1reset <= RESET OR HALT;

-- Instantiate the CPU core
cpu1: TG68KdotC_Kernel 
   generic map(
      SR_Read => 2,              -- Status register read mode (switchable)
      VBR_Stackframe => 2,       -- Vector base register/stack frame (switchable)
      extAddr_Mode => 2,         -- Extended addressing mode (switchable)
      MUL_Mode => 2,             -- Multiply instruction mode (switchable)
      DIV_Mode => 2,             -- Divide instruction mode (switchable)
      BitField => 2,             -- Bit field instructions (switchable)
      BarrelShifter => 0,        -- Barrel shifter disabled
      MUL_Hardware => 1          -- Hardware multiplier enabled
   )
   PORT MAP(
      CPU => CPU,                -- CPU type selection
      clk => CLK,                -- System clock
      nReset => cpu1reset,       -- Active low reset input
      clkena_in => clkena,       -- Clock enable input
      data_in => r_data,         -- Data input from bus
      IPL => cpuIPL,             -- Interrupt priority level
      IPL_autovector => autovector, -- Autovector interrupt mode
      addr_out => ADDR,          -- Address output
      berr => BERR,              -- Bus error input
      FC => FC,                  -- Function codes output
      data_write => data_write,  -- Data to write
      busstate => state,         -- Bus cycle state
      nWr => wr,                 -- Write control (active low)
      nUDS => uds_in,            -- Upper data strobe from core
      nLDS => lds_in,            -- Lower data strobe from core
      nResetOut => nResetOut,    -- Reset output from core
      skipFetch => skipFetch     -- Skip fetch optimization
   );
 
   -- E-clock generation process (6800-compatible synchronous timing)
   -- Creates a 10-state cycle with E high during states 5-9
   PROCESS (CLK)
   BEGIN
      -- E-clock transitions on falling edge of main clock
      IF falling_edge(CLK) THEN
         IF sync_state=sync5 THEN
            E <= '1';    -- E goes high at state 5
         END IF;
         IF sync_state=sync9 THEN
            E <= '0';    -- E goes low at state 9
         END IF;
      END IF;
      
      -- State machine advances on rising edge
      IF rising_edge(CLK) THEN
         CASE sync_state IS
            WHEN sync0  => sync_state <= sync1;
            WHEN sync1  => sync_state <= sync2;
            WHEN sync2  => sync_state <= sync3;
            WHEN sync3  => sync_state <= sync4;
                        -- Sample VPA at state 3 for synchronous peripherals
                        VMA <= VPA;              -- Pass through VPA to VMA
                        vpad <= VPA;             -- Latch VPA for later use
                        autovector <= NOT VPA;   -- VPA low indicates autovector
            WHEN sync4  => sync_state <= sync5;
            WHEN sync5  => sync_state <= sync6;
            WHEN sync6  => sync_state <= sync7;
            WHEN sync7  => sync_state <= sync8;
            WHEN sync8  => sync_state <= sync9;
            WHEN OTHERS => sync_state <= sync0;
                        VMA <= '1';              -- VMA inactive in state 0
         END CASE;
      END IF;
   END PROCESS;

   -- Clock enable generation for CPU core
   -- CPU runs when in state "01", when clkena_e is set, or when skipping fetch
   PROCESS (state, clkena_e, skipFetch)
   BEGIN
      IF state="01" OR clkena_e='1' OR skipFetch='1' THEN
         clkena <= '1';
      ELSE 
         clkena <= '0';
      END IF;
   END PROCESS;

-- Main bus cycle state machine
-- Handles both rising and falling edge operations for proper bus timing
PROCESS (CLK, RESET, state, as_s, as_e, rw_s, rw_e, uds_s, uds_e, lds_s, lds_e)
   BEGIN
      -- Asynchronous reset
      IF RESET='0' THEN
         S_state <= "11";        -- Start in idle state
         as_s <= '1';            -- All signals inactive
         rw_s <= '1';
         uds_s <= '1';
         lds_s <= '1';
         data_akt_s <= '0';
      -- Rising edge operations
      ELSIF rising_edge(CLK) THEN
         -- Default all signals to inactive
         as_s <= '1';
         rw_s <= '1';
         uds_s <= '1';
         lds_s <= '1';
         data_akt_s <= '0';
         
         -- Bus cycle state machine
         CASE S_state IS
            WHEN "00" => -- Wait for CPU to start cycle
                      IF state/="01" AND skipFetch='0' THEN  -- CPU not idle and not skipping
                         IF wr='1' THEN                       -- Read cycle
                            uds_s <= uds_in;                  -- Set data strobes
                            lds_s <= lds_in;
                         END IF;
                         as_s <= '0';                         -- Assert address strobe
                         rw_s <= wr;                          -- Set R/W direction
                         S_state <= "01";                     -- Move to next state
                      END IF;
            WHEN "01" => -- Continue asserting signals
                      as_s <= '0';                            -- Keep AS asserted
                      rw_s <= wr;                             -- Maintain R/W
                      uds_s <= uds_in;                        -- Maintain data strobes
                      lds_s <= lds_in;
                      S_state <= "10";                        -- Move to data phase
            WHEN "10" => -- Data transfer phase
                      data_akt_s <= NOT wr;                   -- Enable data output for writes
                      r_data <= DATA;                         -- Latch read data
                      -- Wait for DTACK or synchronous cycle completion
                      IF waitm='0' OR (vpad='0' AND sync_state=sync9) THEN
                         S_state <= "11";                     -- Cycle complete
                      ELSE	
                         as_s <= '0';                         -- Keep signals asserted
                         rw_s <= wr;
                         uds_s <= uds_in;
                         lds_s <= lds_in;
                      END IF;
            WHEN "11" => -- Idle state
                      S_state <= "00";                        -- Ready for next cycle
            WHEN OTHERS => null;
         END CASE;
      END IF;
      
      -- Falling edge operations (for proper 68K timing)
      IF RESET='0' THEN
         as_e <= '1';
         rw_e <= '1';
         uds_e <= '1';
         lds_e <= '1';
         clkena_e <= '0';
         data_akt_e <= '0';
      ELSIF falling_edge(CLK) THEN
         -- Default all signals to inactive
         as_e <= '1';
         rw_e <= '1';
         uds_e <= '1';
         lds_e <= '1';
         clkena_e <= '0';
         data_akt_e <= '0';
         
         CASE S_state IS
            WHEN "00" => -- Sample interrupt level during idle
                      cpuIPL <= IPL;      -- Latch IPL for HALT command support
            WHEN "01" => -- Assert signals on falling edge
                      data_akt_e <= NOT wr;    -- Enable data for writes
                      as_e <= '0';             -- Assert address strobe
                      rw_e <= wr;              -- Set R/W
                      uds_e <= uds_in;         -- Assert data strobes
                      lds_e <= lds_in;
            WHEN "10" => -- Continue data phase
                      rw_e <= wr;              -- Maintain R/W
                      data_akt_e <= NOT wr;    -- Keep data enabled for writes
                      cpuIPL <= IPL;           -- Sample interrupts
                      waitm <= DTACK;          -- Latch DTACK state
            WHEN OTHERS => -- Cycle complete
                      clkena_e <= '1';         -- Enable CPU for next cycle
         END CASE;
      END IF;
   END PROCESS;
END;
