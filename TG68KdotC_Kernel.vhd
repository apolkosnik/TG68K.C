------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2009-2020 Tobias Gubener                                   -- 
-- Patches by MikeJ, Till Harbaum, Rok Krajnk, ...                          --
-- Subdesign fAMpIGA by TobiFlex                                            --
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

-- Revision History:
-- 14.10.2020 TG bugfix chk2.b
-- 13.10.2020 TG go back to old aligned design and bugfix chk2
-- 11.10.2020 TG next try CHK2 flags
-- 10.10.2020 TG bugfix division N-flag
-- 09.10.2020 TG bugfix division overflow
-- 2/3.10.2020 some tweaks by retrofun, gyurco and robinsonb5
-- 17.03.2020 TG bugfix move data to (extended address)
-- 13.03.2020 TG bugfix extended addess mode - thanks Adam Polkosnik
-- 15.02.2020 TG bugfix DIVS.W with result $8000
-- 08.01.2020 TH fix the byte-mirroring
-- 25.11.2019 TG bugfix ILLEGAL.B handling
-- 24.11.2019 TG next try CMP2 and CHK2.l
-- 24.11.2019 retrofun(RF) commit ILLEGAL.B handling 
-- 18.11.2019 TG insert CMP2 and CHK2.l
-- 17.11.2019 TG insert CAS and CAS2
-- 10.11.2019 TG insert TRAPcc
-- 08.11.2019 TG bugfix movem in 68020 mode
-- 06.11.2019 TG bugfix CHK
-- 06.11.2019 TG bugfix flags and stackframe DIVU
-- 04.11.2019 TG insert RTE from TH
-- 03.11.2019 TG insert TrapV from TH 
-- 03.11.2019 TG bugfix MUL 64Bit 
-- 03.11.2019 TG rework barrel shifter - some other tweaks
-- 02.11.2019 TG bugfig N-Flag and Z-Flag for DIV
-- 30.10.2019 TG bugfix RTR in 68020-mode
-- 30.10.2019 TG bugfix BFINS again
-- 19.10.2019 TG insert some bugfixes from apolkosnik
-- 05.12.2018 TG insert RTD opcode
-- 03.12.2018 TG insert barrel shifter
-- 01.11.2017 TG bugfix V-Flag for ASL/ASR - thanks Peter Graf
-- 29.05.2017 TG decode 0x4AFB as illegal, needed for QL BKP - thanks Peter Graf
-- 21.05.2017 TG insert generic for hardware multiplier for MULU & MULS
-- 04.04.2017 TG change GPL to LGPL
-- 04.04.2017 TG BCD handling with all undefined behavior! 
-- 02.04.2017 TG bugfix Bitfield Opcodes 
-- 19.03.2017 TG insert PACK/UNPACK  
-- 19.03.2017 TG bugfix CMPI ...(PC) - thanks Till Harbaum
--     ???    MJ bugfix non_aligned movem access
-- add berr handling 10.03.2013 - needed for ATARI Core

-- bugfix session 07/08.Feb.2013
-- movem ,-(an)
-- movem (an)+,          - thanks  Gerhard Suttner
-- btst dn,#data         - thanks  Peter Graf
-- movep                 - thanks  Till Harbaum
-- IPL vector            - thanks  Till Harbaum
--  

-- optimize Register file

-- to do 68010:
-- (MOVEC)
-- BKPT
-- MOVES
--
-- to do 68020:
-- (CALLM)
-- (RETM)

-- bugfix CHK2, CMP2
-- rework barrel shifter 
-- CHK2
-- CMP2
-- cpXXX Coprozessor stuff

-- done 020:
-- CAS, CAS2
-- TRAPcc
-- PACK
-- UNPK
-- Bitfields
-- address modes
-- long bra
-- DIVS.L, DIVU.L
-- LINK long
-- MULS.L, MULU.L
-- extb.l

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.TG68K_Pack.all;

entity TG68KdotC_Kernel is
	generic(
		-- Configuration parameters for CPU features
		SR_Read : integer:= 2;				--0=>user, 1=>privileged, 2=>switchable with CPU(0)
		VBR_Stackframe : integer:= 2;		--0=>no, 1=>yes/extended, 2=>switchable with CPU(0)
		extAddr_Mode : integer:= 2;			--0=>no, 1=>yes, 2=>switchable with CPU(1)
		MUL_Mode : integer := 2;			--0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no MUL
		DIV_Mode : integer := 2;			--0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no DIV
		BitField : integer := 2;			--0=>no, 1=>yes, 2=>switchable with CPU(1) 
		
		BarrelShifter : integer := 1;		--0=>no, 1=>yes, 2=>switchable with CPU(1)
		MUL_Hardware : integer := 1			--0=>no, 1=>yes
		);
	port(
		-- System signals
		clk						: in std_logic;
		nReset					: in std_logic;			--low active reset
		clkena_in				: in std_logic:='1';	--clock enable input
		
		-- Data bus interface
		data_in					: in std_logic_vector(15 downto 0);
		IPL						: in std_logic_vector(2 downto 0):="111";		-- Interrupt Priority Level (active low)
		IPL_autovector			: in std_logic:='0';							-- Use autovector for interrupts
		berr					: in std_logic:='0';							-- Bus error signal
		CPU						: in std_logic_vector(1 downto 0):="00";		-- CPU mode: 00->68000, 01->68010, 11->68020
		
		-- Memory interface outputs
		addr_out				: out std_logic_vector(31 downto 0);
		data_write				: out std_logic_vector(15 downto 0);
		nWr						: out std_logic;		-- Write strobe (active low)
		nUDS					: out std_logic;		-- Upper Data Strobe (active low)
		nLDS					: out std_logic;		-- Lower Data Strobe (active low)
		busstate				: out std_logic_vector(1 downto 0);	-- 00->fetch code, 10->read data, 11->write data, 01->no memaccess
		longword				: out std_logic;		-- Indicates longword access
		nResetOut				: out std_logic;		-- Reset output for RESET instruction
		FC						: out std_logic_vector(2 downto 0);		-- Function codes
		clr_berr				: out std_logic;		-- Clear bus error
		
		-- Debug outputs
		skipFetch				: out std_logic;
		regin_out				: out std_logic_vector(31 downto 0);
		CACR_out				: out std_logic_vector( 3 downto 0);		-- Cache Control Register
		VBR_out					: out std_logic_vector(31 downto 0)		-- Vector Base Register
		);
end TG68KdotC_Kernel;

architecture logic of TG68KdotC_Kernel is

	-- Configuration signal
	signal use_VBR_Stackframe	: std_logic;

	-- Reset and clock control signals
	signal syncReset			: std_logic_vector(3 downto 0);
	signal Reset				: std_logic;
	signal clkena_lw			: std_logic;	-- Clock enable for longword operations
	
	-- Program Counter related signals
	signal TG68_PC				: std_logic_vector(31 downto 0);		-- Current PC
	signal tmp_TG68_PC			: std_logic_vector(31 downto 0);		-- Temporary PC storage
	signal TG68_PC_add			: std_logic_vector(31 downto 0);		-- PC + offset
	signal PC_dataa				: std_logic_vector(31 downto 0);		-- PC operand A
	signal PC_datab				: std_logic_vector(31 downto 0);		-- PC operand B
	
	-- Memory addressing signals
	signal memaddr				: std_logic_vector(31 downto 0);		-- Memory address
	signal state				: std_logic_vector(1 downto 0);			-- Memory state machine
	signal datatype				: std_logic_vector(1 downto 0);			-- 00=byte, 01=word, 10=long
	signal set_datatype			: std_logic_vector(1 downto 0);
	signal exe_datatype			: std_logic_vector(1 downto 0);
	signal setstate				: std_logic_vector(1 downto 0);
	signal setaddrvalue			: std_logic;
	signal addrvalue			: std_logic;

	-- Instruction opcodes
	signal opcode				: std_logic_vector(15 downto 0);		-- Current opcode
	signal exe_opcode			: std_logic_vector(15 downto 0);		-- Executing opcode
	signal sndOPC				: std_logic_vector(15 downto 0);		-- Second opcode word

	-- Execution tracking
	signal exe_pc				: std_logic_vector(31 downto 0);		-- PC of executing instruction
	signal last_opc_pc			: std_logic_vector(31 downto 0);		-- PC of last opcode
	signal last_opc_read		: std_logic_vector(15 downto 0);		-- Last opcode read
	
	-- Register file interface signals
	signal registerin			: std_logic_vector(31 downto 0);
	signal reg_QA				: std_logic_vector(31 downto 0);		-- Register output A
	signal reg_QB				: std_logic_vector(31 downto 0);		-- Register output B
	signal Wwrena,Lwrena		: bit;									-- Word/Long write enables
	signal Bwrena				: bit;									-- Byte write enable
	signal Regwrena_now			: bit;									-- Immediate register write
	signal rf_dest_addr			: std_logic_vector(3 downto 0);			-- Destination register address
	signal rf_source_addr		: std_logic_vector(3 downto 0);			-- Source register address
	signal rf_source_addrd		: std_logic_vector(3 downto 0);			-- Delayed source address
   
	-- Register file
	signal regin				: std_logic_vector(31 downto 0);		-- Register input data
	type   regfile_t is array(0 to 15) of std_logic_vector(31 downto 0);
	signal regfile				: regfile_t := (OTHERS => (OTHERS => '0')); -- 16 x 32-bit registers (D0-D7, A0-A7)
	signal RDindex_A			: integer range 0 to 15;
	signal RDindex_B			: integer range 0 to 15;
	signal WR_AReg				: std_logic;							-- Writing to address register

	-- Address calculation signals
	signal addr					: std_logic_vector(31 downto 0);
	signal memaddr_reg			: std_logic_vector(31 downto 0);
	signal memaddr_delta		: std_logic_vector(31 downto 0);
	signal memaddr_delta_rega	: std_logic_vector(31 downto 0);
	signal memaddr_delta_regb	: std_logic_vector(31 downto 0);
	signal use_base				: bit;
	
	-- Effective address calculation
	signal ea_data				: std_logic_vector(31 downto 0);		-- Effective address data
	signal OP1out				: std_logic_vector(31 downto 0);		-- Operand 1 output
	signal OP2out				: std_logic_vector(31 downto 0);		-- Operand 2 output
	signal OP1outbrief			: std_logic_vector(15 downto 0);		-- Brief extension word
	signal OP1in				: std_logic_vector(31 downto 0);		-- Operand 1 input
	signal ALUout				: std_logic_vector(31 downto 0);		-- ALU output
	signal data_write_tmp		: std_logic_vector(31 downto 0);		-- Temporary write data
	signal data_write_muxin		: std_logic_vector(31 downto 0);
	signal data_write_mux		: std_logic_vector(47 downto 0);		-- Write data multiplexer
	
	-- Control signals
	signal nextpass				: bit;
	signal setnextpass			: bit;
	signal setdispbyte			: bit;
	signal setdisp				: bit;
	signal regdirectsource		: bit;
	signal addsub_q				: std_logic_vector(31 downto 0);
	signal briefdata			: std_logic_vector(31 downto 0);
	signal c_out				: std_logic_vector(2 downto 0);			-- Carry out signals

	-- Memory access control
	signal mem_address			: std_logic_vector(31 downto 0);
	signal memaddr_a			: std_logic_vector(31 downto 0);

	-- PC control signals
	signal TG68_PC_brw			: bit;									-- PC branch/write
	signal TG68_PC_word			: bit;									-- PC word access
	signal getbrief				: bit;									-- Get brief extension word
	signal brief				: std_logic_vector(15 downto 0);		-- Brief extension word storage
	signal data_is_source		: bit;
	signal store_in_tmp			: bit;
	signal write_back			: bit;
	signal exec_write_back		: bit;
	signal setstackaddr			: bit;
	signal writePC				: bit;
	signal writePCbig			: bit;
	signal set_writePCbig		: bit;
	signal writePCnext			: bit;
	
	-- Instruction execution control
	signal setopcode			: bit;
	signal decodeOPC			: bit;
	signal execOPC				: bit;
	signal execOPC_ALU			: bit;
	signal setexecOPC			: bit;
	signal endOPC				: bit;
	signal setendOPC			: bit;
	
	-- Status register and flags
	signal Flags				: std_logic_vector(7 downto 0);			-- ...XNZVC flags
	signal FlagsSR				: std_logic_vector(7 downto 0);			-- T.S.0III (Trace, Supervisor, Interrupt mask)
	signal SRin					: std_logic_vector(7 downto 0);			-- Status register input
	signal exec_DIRECT			: bit;
	signal exec_tas				: std_logic;
	signal set_exec_tas			: std_logic;

	-- Condition code evaluation
	signal exe_condition		: std_logic;
	
	-- Effective address control signals
	signal ea_only				: bit;
	signal source_areg			: std_logic;
	signal source_lowbits		: bit;
	signal source_LDRLbits 		: bit;
	signal source_LDRMbits 		: bit;
	signal source_2ndHbits		: bit;
	signal source_2ndMbits		: bit;
	signal source_2ndLbits		: bit;
	signal dest_areg			: std_logic;
	signal dest_LDRareg			: std_logic;
	signal dest_LDRHbits		: bit;
	signal dest_LDRLbits		: bit;
	signal dest_2ndHbits		: bit;
	signal dest_2ndLbits		: bit;
	signal dest_hbits			: bit;
	
	-- Rotation/shift control
	signal rot_bits				: std_logic_vector(1 downto 0);
	signal set_rot_bits			: std_logic_vector(1 downto 0);
	signal rot_cnt				: std_logic_vector(5 downto 0);			-- Rotation count
	signal set_rot_cnt			: std_logic_vector(5 downto 0);
	
	-- MOVEM instruction control
	signal movem_actiond		: bit;
	signal movem_regaddr		: std_logic_vector(3 downto 0);
	signal movem_mux			: std_logic_vector(3 downto 0);
	signal movem_presub			: bit;
	signal movem_run			: bit;
	signal ea_calc_b			: std_logic_vector(31 downto 0);
	signal set_direct_data		: bit;
	signal use_direct_data		: bit;
	signal direct_data			: bit;

	-- Exception handling signals
	signal set_V_Flag			: bit;
	signal set_vectoraddr		: bit;
	signal writeSR				: bit;
	signal trap_berr			: bit;									-- Bus error trap
	signal trap_illegal			: bit;									-- Illegal instruction trap
	signal trap_addr_error		: bit;									-- Address error trap
	signal trap_priv			: bit;									-- Privilege violation trap
	signal trap_trace			: bit;									-- Trace trap
	signal trap_1010			: bit;									-- Line 1010 emulator trap
	signal trap_1111			: bit;									-- Line 1111 emulator trap
	signal trap_trap			: bit;									-- TRAP instruction trap
	signal trap_trapv			: bit;									-- TRAPV trap
	signal trap_interrupt		: bit;									-- Interrupt trap
	signal trapmake				: bit;									-- Generate trap
	signal trapd				: bit;									-- Trap delayed
	signal trap_SR				: std_logic_vector(7 downto 0);			-- SR at trap time
	signal make_trace			: std_logic;
	signal make_berr			: std_logic;
	signal useStackframe2		: std_logic;							-- Use stack frame format 2
	
	-- CPU state control
	signal set_stop				: bit;									-- Set STOP state
	signal stop					: bit;									-- CPU stopped
	signal trap_vector			: std_logic_vector(31 downto 0);		-- Trap vector number
	signal trap_vector_vbr		: std_logic_vector(31 downto 0);		-- Trap vector + VBR
	signal USP					: std_logic_vector(31 downto 0);		-- User Stack Pointer

	-- Interrupt handling
	signal IPL_nr				: std_logic_vector(2 downto 0);			-- Current IPL
	signal rIPL_nr				: std_logic_vector(2 downto 0);			-- Registered IPL
	signal IPL_vec				: std_logic_vector(7 downto 0);			-- Interrupt vector
	signal interrupt			: bit;
	signal setinterrupt			: bit;
	signal SVmode				: std_logic;							-- Supervisor mode
	signal preSVmode			: std_logic;							-- Previous supervisor mode
	signal Suppress_Base		: bit;
	signal set_Suppress_Base	: bit;
	signal set_Z_error 			: bit;									-- Division by zero error
	signal Z_error 				: bit;
	signal ea_build_now			: bit;	
	signal build_logical		: bit;	
	signal build_bcd			: bit;									-- Build BCD operation
	
	-- Data read handling
	signal data_read			: std_logic_vector(31 downto 0);
	signal bf_ext_in			: std_logic_vector(7 downto 0);			-- Bit field extract input
	signal bf_ext_out			: std_logic_vector(7 downto 0);			-- Bit field extract output
	signal long_start			: bit;									-- Long operation start
	signal long_start_alu		: bit;
	signal non_aligned			: std_logic;							-- Non-aligned access
	signal check_aligned		: std_logic;							-- Check alignment
	signal long_done			: bit;									-- Long operation done
	signal memmask				: std_logic_vector(5 downto 0);			-- Memory access mask
	signal set_memmask			: std_logic_vector(5 downto 0);
	signal memread				: std_logic_vector(3 downto 0);			-- Memory read control
	signal wbmemmask			: std_logic_vector(5 downto 0);			-- Write back memory mask
	signal memmaskmux			: std_logic_vector(5 downto 0);			-- Memory mask multiplexer
	signal oddout				: std_logic;							-- Odd address output
	signal set_oddout			: std_logic;
	signal PCbase				: std_logic;							-- PC relative addressing
	signal set_PCbase			: std_logic;
		 
	signal last_data_read		: std_logic_vector(31 downto 0);
	signal last_data_in			: std_logic_vector(31 downto 0);

	-- Bit field instruction signals
	signal bf_offset			: std_logic_vector(5 downto 0);			-- Bit field offset
	signal bf_width				: std_logic_vector(5 downto 0);			-- Bit field width
	signal bf_bhits				: std_logic_vector(5 downto 0);			-- Bit field boundary hits
	signal bf_shift				: std_logic_vector(5 downto 0);			-- Bit field shift amount
	signal alu_width			: std_logic_vector(5 downto 0);
	signal alu_bf_shift			: std_logic_vector(5 downto 0);
	signal bf_loffset			: std_logic_vector(5 downto 0);
	signal bf_full_offset		: std_logic_vector(31 downto 0);
	signal alu_bf_ffo_offset	: std_logic_vector(31 downto 0);
	signal alu_bf_loffset		: std_logic_vector(5 downto 0);

	-- MOVEC instruction registers
	signal movec_data			: std_logic_vector(31 downto 0);
	signal VBR					: std_logic_vector(31 downto 0);		-- Vector Base Register
	signal CACR					: std_logic_vector(3 downto 0);			-- Cache Control Register
	signal DFC					: std_logic_vector(2 downto 0);			-- Destination Function Code
	signal SFC					: std_logic_vector(2 downto 0);			-- Source Function Code
	
	-- Microcode execution control
	signal set					: bit_vector(lastOpcBit downto 0);		-- Set microcode bits
	signal set_exec				: bit_vector(lastOpcBit downto 0);		-- Set execution bits
	signal exec					: bit_vector(lastOpcBit downto 0);		-- Execution bits

	-- Microcode state machine
	signal micro_state			: micro_states;
	signal next_micro_state		: micro_states;
	
BEGIN  

-- ALU instantiation - handles arithmetic and logical operations
ALU: TG68K_ALU   
	generic map(
		MUL_Mode => MUL_Mode,				--0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no MUL
		MUL_Hardware => MUL_Hardware,		--0=>no, 1=>yes
		DIV_Mode => DIV_Mode,				--0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no DIV
		BarrelShifter => BarrelShifter		--0=>no, 1=>yes, 2=>switchable with CPU(1)  
		)
	port map(
		clk => clk,
		Reset => Reset,
		CPU => CPU,
		clkena_lw => clkena_lw,
		execOPC => execOPC_ALU,
		decodeOPC => decodeOPC,
		exe_condition => exe_condition,
		exec_tas => exec_tas,
		long_start => long_start_alu,
		non_aligned => non_aligned,
		check_aligned => check_aligned,
		movem_presub => movem_presub,
		set_stop => set_stop,
		Z_error => Z_error,

		rot_bits => rot_bits,
		exec => exec,
		OP1out => OP1out,
		OP2out => OP2out,
		reg_QA => reg_QA,
		reg_QB => reg_QB,
		opcode => opcode,
		exe_opcode => exe_opcode,
		exe_datatype => exe_datatype,
		sndOPC => sndOPC,
		last_data_read => last_data_read(15 downto 0),
		data_read => data_read(15 downto 0),
		FlagsSR => FlagsSR,
		micro_state => micro_state,
		bf_ext_in => bf_ext_in,
		bf_ext_out => bf_ext_out,
		bf_shift => alu_bf_shift,
		bf_width => alu_width,
		bf_ffo_offset => alu_bf_ffo_offset,
		bf_loffset => alu_bf_loffset(4 downto 0),

		set_V_Flag => set_V_Flag,
		Flags => Flags,
		c_out => c_out,
		addsub_q => addsub_q,
		ALUout => ALUout
	);

	-- Longword access indicator for parent module (enables burst writes)
	longword <= not memmaskmux(3);
	
	-- ALU control signals
	long_start_alu <= to_bit(NOT memmaskmux(3));
	execOPC_ALU <= execOPC OR exec(alu_exec);
	
	-- Non-aligned memory access detection
	process (memmaskmux)
	begin
		non_aligned <= '0';
		if (memmaskmux(5 downto 4) = "01") or (memmaskmux(5 downto 4) = "10") then
			non_aligned <= '1';
		end if;
	end process;
	
-----------------------------------------------------------------------------
-- Bus control - manages external memory interface
-----------------------------------------------------------------------------
	regin_out <= regin;

	-- Memory interface control signals
	nWr <= '0' WHEN state="11" ELSE '1';		-- Write strobe (active during write state)
	busstate <= state;							-- Export bus state
	nResetOut <= '0' WHEN exec(opcRESET)='1' ELSE '1';		-- RESET instruction output
	
	-- Memory mask multiplexer - handles byte lane selection
	-- Shifts mask for odd byte addresses on 68000
	memmaskmux <= memmask when addr(0) = '1' else memmask(4 downto 0) & '1';
	nUDS <= memmaskmux(5);		-- Upper data strobe
	nLDS <= memmaskmux(4);		-- Lower data strobe
	
	-- Clock enable for longword operations
	clkena_lw <= '1' WHEN clkena_in='1' AND memmaskmux(3)='1' ELSE '0';
	
	-- Bus error clear signal
	clr_berr <= '1' WHEN setopcode='1' AND trap_berr='1' ELSE '0';
	
	-- Reset synchronization and configuration
	PROCESS (clk, nReset)
	BEGIN
		IF nReset='0' THEN
			syncReset <= "0000";
			Reset <= '1'; 
	  	ELSIF rising_edge(clk) THEN
			IF clkena_in='1' THEN
				-- Synchronize reset release
				syncReset <= syncReset(2 downto 0)&'1';
				Reset <= NOT syncReset(3);	
			END IF;
		END IF;
		IF rising_edge(clk) THEN
			-- Configure VBR and stack frame usage based on CPU type
			IF VBR_Stackframe=1 or (cpu(0)='1' and VBR_Stackframe=2) THEN
				use_VBR_Stackframe<='1';
			ELSE
				use_VBR_Stackframe<='0';
			END IF;
		END IF;
	END PROCESS;
			
-- Data read handling and alignment
PROCESS (clk, long_done, last_data_in, data_in, addr, long_start, memmaskmux, memread, memmask, data_read)
	BEGIN
		-- Align incoming data based on byte lanes
		IF memmaskmux(4)='0' THEN
			data_read <= last_data_in(15 downto 0)&data_in;
		ELSE
			data_read <= last_data_in(23 downto 0)&data_in(15 downto 8);
		END IF;
		
		-- Sign extend for byte/word reads
		IF memread(0)='1' OR (memread(1 downto 0)="10" AND memmaskmux(4)='1')THEN
			data_read(31 downto 16) <= (OTHERS=>data_read(15));
		END IF;	
		
		IF rising_edge(clk) THEN	
			-- Extract byte for bit field operations
			IF clkena_lw='1' AND state="10" THEN
				IF memmaskmux(4)='0' THEN
					bf_ext_in <= last_data_in(23 downto 16);
				ELSE
					bf_ext_in <= last_data_in(31 downto 24);
				END IF;
			END IF;	
			
			IF Reset='1' THEN
				last_data_read <= (OTHERS => '0');
			ELSIF clkena_in='1' THEN
				-- Update last data read
				IF state="00" OR exec(update_ld)='1' THEN 
					last_data_read <= data_read;
					IF state(1)='0' AND memmask(1)='0' THEN
						last_data_read(31 downto 16) <= last_opc_read;
					ELSIF state(1)='0' OR memread(1)='1' THEN
						last_data_read(31 downto 16) <= (OTHERS=>data_in(15));
					END IF;
				END IF;
				-- Shift register for incoming data
				last_data_in <= last_data_in(15 downto 0)&data_in(15 downto 0);
			END IF;
		END IF;
		
		-- Long operation control
		long_start <= to_bit(NOT memmask(1));
		long_done <= to_bit(NOT memread(1));
	END PROCESS;
	
-- Data write multiplexing and alignment
PROCESS (long_start, reg_QB, data_write_tmp, exec, data_read, data_write_mux, memmaskmux, bf_ext_out, 
		 data_write_muxin, memmask, oddout, addr)
	BEGIN
		-- Select write data source
		IF exec(write_reg)='1' THEN
			data_write_muxin <= reg_QB;
		ELSE
			data_write_muxin <= data_write_tmp;
		END IF;
		
		-- Arrange data for bit field operations
		IF BitField=0 THEN
			IF oddout=addr(0) THEN
				data_write_mux <= "--------"&"--------"&data_write_muxin;
			ELSE
				data_write_mux <= "--------"&data_write_muxin&"--------";
			END IF;
		ELSE
			IF oddout=addr(0) THEN
				data_write_mux <= "--------"&bf_ext_out&data_write_muxin;
			ELSE
				data_write_mux <= bf_ext_out&data_write_muxin&"--------";
			END IF;
		END IF;
		
		-- Select output data based on operation size
		IF memmaskmux(1)='0' THEN
			data_write <= data_write_mux(47 downto 32);
		ELSIF memmaskmux(3)='0' THEN	
			data_write <= data_write_mux(31 downto 16);
		ELSE
			-- Single byte appears on both bus halves
			IF memmaskmux(5 downto 4) = "10" THEN
				data_write <= data_write_mux(7 downto 0) & data_write_mux(7 downto 0);
			ELSIF memmaskmux(5 downto 4) = "01" THEN
				data_write <= data_write_mux(15 downto 8) & data_write_mux(15 downto 8);
			ELSE
				data_write <= data_write_mux(15 downto 0);
			END IF;
		END IF;
		
		-- MOVEP instruction special case
		IF exec(mem_byte)='1' THEN
			data_write <= data_write_tmp(15 downto 8) & data_write_tmp(15 downto 8);
		END IF;
	END PROCESS;
	
-----------------------------------------------------------------------------
-- Register file - 16 x 32-bit registers (D0-D7, A0-A7)
-----------------------------------------------------------------------------
PROCESS (clk, regfile, RDindex_A, RDindex_B, exec)
	BEGIN
		-- Asynchronous read ports
		reg_QA <= regfile(RDindex_A);
		reg_QB <= regfile(RDindex_B);
		
		IF rising_edge(clk) THEN
		    IF clkena_lw='1' THEN
				-- Register address setup
				rf_source_addrd <= rf_source_addr;
				WR_AReg <= rf_dest_addr(3);		-- Bit 3 indicates address register
				RDindex_A <= conv_integer(rf_dest_addr(3 downto 0));
				RDindex_B <= conv_integer(rf_source_addr(3 downto 0));
				
				-- Register write
				IF Wwrena='1' THEN
					regfile(RDindex_A) <= regin;
				END IF;
				
				-- User Stack Pointer handling
				IF exec(to_USP)='1' THEN
					USP <= reg_QA;
				END IF;	
			END IF;
		END IF;
	END PROCESS;

-----------------------------------------------------------------------------
-- Write Register logic - determines what data to write to registers
-----------------------------------------------------------------------------
PROCESS (OP1in, reg_QA, Regwrena_now, Bwrena, Lwrena, exe_datatype, WR_AReg, movem_actiond, exec, ALUout, memaddr, memaddr_a, ea_only, USP, movec_data)
	BEGIN
		-- Default: write ALU output
		regin <= ALUout;
		
		-- Special cases for register input data
		IF exec(save_memaddr)='1' THEN
			regin <= memaddr;	
		ELSIF exec(get_ea_now)='1' AND ea_only='1' THEN
			regin <= memaddr_a;	
		ELSIF exec(from_USP)='1' THEN
			regin <= USP;	
		ELSIF exec(movec_rd)='1' THEN
			regin <= movec_data;
		END IF;
		
		-- Preserve upper bytes for byte operations
		IF Bwrena='1' THEN
			regin(15 downto 8) <= reg_QA(15 downto 8);
		END IF;
		-- Preserve upper word for word operations
		IF Lwrena='0' THEN
			regin(31 downto 16) <= reg_QA(31 downto 16);
		END IF;

		-- Write enable logic
		Bwrena <= '0';
		Wwrena <= '0';
		Lwrena <= '0';
		
		-- Pre-decrement and post-increment operations
		IF exec(presub)='1' OR exec(postadd)='1' OR exec(changeMode)='1' THEN
			Wwrena <= '1';
			Lwrena <= '1';
		ELSIF Regwrena_now='1' THEN		-- DBcc immediate write
			Wwrena <= '1';
		ELSIF exec(Regwrena)='1' THEN		-- Normal register write
			Wwrena <= '1';
			CASE exe_datatype IS
				WHEN "00" =>		-- BYTE
					Bwrena <= '1';
				WHEN "01" =>		-- WORD
					IF WR_AReg='1' OR movem_actiond='1' THEN
						Lwrena <='1';	-- Sign extend to long for address registers
					END IF;
				WHEN OTHERS =>		-- LONG
					Lwrena <= '1';
			END CASE;
		END IF;	
	END PROCESS;
	
-----------------------------------------------------------------------------
-- Set destination register address - determines which register to write to
-----------------------------------------------------------------------------
PROCESS (opcode, rf_source_addrd, brief, setstackaddr, dest_hbits, dest_areg, dest_LDRareg, data_is_source, sndOPC, exec, set, dest_2ndHbits, dest_2ndLbits, dest_LDRHbits, dest_LDRLbits, last_data_read)
	BEGIN
		IF exec(movem_action) ='1' THEN
			-- MOVEM uses source as destination during restore
			rf_dest_addr <= rf_source_addrd;
		ELSIF set(briefext)='1' THEN
			-- Brief extension word specifies register
			rf_dest_addr <= brief(15 downto 12);
		ELSIF set(get_bfoffset)='1' THEN
			-- Bit field offset register
			rf_dest_addr <= '0'&sndOPC(8 downto 6);
		ELSIF dest_2ndHbits='1' THEN
			-- Second word high bits specify register
			rf_dest_addr <= dest_LDRareg&sndOPC(14 downto 12);
		ELSIF dest_LDRHbits='1' THEN
			-- Last data read high bits
			rf_dest_addr <= last_data_read(15 downto 12);
		ELSIF dest_LDRLbits='1' THEN
			-- Last data read low bits (data register)
			rf_dest_addr <= '0'&last_data_read(2 downto 0);
		ELSIF dest_2ndLbits='1' THEN
			-- Second word low bits (data register)
			rf_dest_addr <= '0'&sndOPC(2 downto 0);
		ELSIF setstackaddr='1' THEN	
			-- Stack pointer (A7)
			rf_dest_addr <= "1111";
		ELSIF dest_hbits='1' THEN	
			-- Opcode bits 11-9 specify register
			rf_dest_addr <= dest_areg&opcode(11 downto 9);
		ELSE
			-- Default: effective address field
			IF opcode(5 downto 3)="000" OR data_is_source='1' THEN 			
				rf_dest_addr <= dest_areg&opcode(2 downto 0);
			ELSE
				-- Force to address register for certain EA modes
				rf_dest_addr <= '1'&opcode(2 downto 0);
			END IF;
		END IF;	
	END PROCESS;
	
-----------------------------------------------------------------------------
-- Set source register address - determines which register to read from
-----------------------------------------------------------------------------
PROCESS (opcode, movem_presub, movem_regaddr, source_lowbits, source_areg, sndOPC, exec, set, source_2ndLbits, source_2ndHbits, source_LDRLbits, source_LDRMbits, last_data_read, source_2ndMbits)
	BEGIN
		IF exec(movem_action)='1' OR set(movem_action) ='1' THEN
			-- MOVEM register selection with pre-decrement reversal
			IF movem_presub='1' THEN
				rf_source_addr <= movem_regaddr XOR "1111";
			ELSE
				rf_source_addr <= movem_regaddr;
			END IF; 
		ELSIF source_2ndLbits='1' THEN
			-- Second word low bits
			rf_source_addr <= '0'&sndOPC(2 downto 0);
		ELSIF source_2ndHbits='1' THEN
			-- Second word high bits
			rf_source_addr <= '0'&sndOPC(14 downto 12);
		ELSIF source_2ndMbits='1' THEN
			-- Second word middle bits
			rf_source_addr <= '0'&sndOPC(8 downto 6);
		ELSIF source_LDRLbits='1' THEN
			-- Last data read low bits
			rf_source_addr <= '0'&last_data_read(2 downto 0);
		ELSIF source_LDRMbits='1' THEN
			-- Last data read middle bits
			rf_source_addr <= '0'&last_data_read(8 downto 6);
		ELSIF source_lowbits='1' THEN
			-- EA field as source
			rf_source_addr <= source_areg&opcode(2 downto 0);
		ELSIF exec(linksp)='1' THEN
			-- LINK uses stack pointer
			rf_source_addr <= "1111";
		ELSE
			-- Default: register field (bits 11-9)
			rf_source_addr <= source_areg&opcode(11 downto 9);
		END IF;	
	END PROCESS;
	
-----------------------------------------------------------------------------
-- Set OP1out - first operand for ALU
-----------------------------------------------------------------------------
PROCESS (reg_QA, store_in_tmp, ea_data, long_start, addr, exec, memmaskmux)
	BEGIN
		-- Default: register value
		OP1out <= reg_QA;
		
		IF exec(OP1out_zero)='1' THEN
			-- Force to zero
			OP1out <= (OTHERS => '0');	
		ELSIF exec(ea_data_OP1)='1' AND store_in_tmp='1' THEN
			-- Use effective address data
			OP1out <= ea_data;
		ELSIF exec(movem_action)='1' OR memmaskmux(3)='0' OR exec(OP1addr)='1' THEN 
			-- Use address for MOVEM or long operations
			OP1out <= addr;
		END IF;
	END PROCESS;
	
-----------------------------------------------------------------------------
-- Set OP2out - second operand for ALU
-----------------------------------------------------------------------------
PROCESS (OP2out, reg_QB, exe_opcode, exe_datatype, execOPC, exec, use_direct_data, 
	     store_in_tmp, data_write_tmp, ea_data)
	BEGIN
		-- Default: register value
		OP2out(15 downto 0) <= reg_QB(15 downto 0);
		OP2out(31 downto 16) <= (OTHERS => OP2out(15));	-- Sign extend
		
		IF exec(OP2out_one)='1' THEN
			-- Force to -1
			OP2out(15 downto 0) <= "1111111111111111";
		ELSIF use_direct_data='1' OR (exec(exg)='1' AND execOPC='1') OR exec(get_bfoffset)='1' THEN	
			-- Use temporary data
			OP2out <= data_write_tmp;	
		ELSIF (exec(ea_data_OP1)='0' AND store_in_tmp='1') OR exec(ea_data_OP2)='1' THEN
			-- Use effective address data
			OP2out <= ea_data;	
		ELSIF exec(opcMOVEQ)='1' THEN
			-- MOVEQ immediate data
			OP2out(7 downto 0) <= exe_opcode(7 downto 0);
			OP2out(15 downto 8) <= (OTHERS => exe_opcode(7));
		ELSIF exec(opcADDQ)='1' THEN
			-- ADDQ/SUBQ immediate data (1-8 encoded as 0-7)
			OP2out(2 downto 0) <= exe_opcode(11 downto 9);
			IF exe_opcode(11 downto 9)="000" THEN
				OP2out(3) <='1';	-- 0 means 8
			ELSE
				OP2out(3) <='0';
			END IF;
			OP2out(15 downto 4) <= (OTHERS => '0');
		ELSIF exe_datatype="10" AND exec(opcEXT)='0'  THEN 
			-- Long operations preserve upper word
			OP2out(31 downto 16) <= reg_QB(31 downto 16);
		END IF;
		
		-- EXTB.L sign extends from byte
		IF exec(opcEXTB)='1' THEN
			OP2out(31 downto 8) <= (OTHERS => OP2out(7));		
		END IF;
	END PROCESS;
	

-----------------------------------------------------------------------------
-- Handle EA_data and data_write - manages temporary data storage
-----------------------------------------------------------------------------
PROCESS (clk)
	BEGIN
     	IF rising_edge(clk) THEN
			IF Reset = '1' THEN
				store_in_tmp <='0';
				direct_data <= '0';
				use_direct_data <= '0';
				Z_error <= '0';
				writePCnext <= '0';
			ELSIF clkena_lw='1' THEN
				useStackframe2<='0';
				direct_data <= '0';
				
				-- Direct data usage control
				IF exec(hold_OP2)='1' THEN
					use_direct_data <= '1';
				END IF;
				IF set_direct_data='1' THEN
					direct_data <= '1';
					use_direct_data <= '1';
				ELSIF endOPC='1' OR set(ea_data_OP2)='1' THEN	
					use_direct_data <= '0';
				END IF;	
				exec_DIRECT <= set_exec(opcMOVE);
				
				IF endOPC='1' THEN
					store_in_tmp <='0';
					Z_error <= '0';
					writePCnext <= '0';
				ELSE
					IF set_Z_error='1'  THEN
						Z_error <= '1';
					END IF;	
					IF set_exec(opcMOVE)='1' AND state="11" THEN
						use_direct_data <= '1';
					END IF;

					-- Store data in temporary location
					IF state="10" OR exec(store_ea_packdata)='1' THEN
						store_in_tmp <= '1'; 
					END IF;
					IF direct_data='1' AND state="00" THEN
						store_in_tmp <= '1'; 
					END IF;	
				END IF;
				
				-- EA data handling
				IF state="10" AND exec(hold_ea_data)='0' THEN
					ea_data <= data_read;
				ELSIF exec(get_2ndOPC)='1' THEN
					ea_data <= addr;
				ELSIF exec(store_ea_data)='1' OR (direct_data='1' AND state="00") THEN
					ea_data <= last_data_read;
				END IF;	
				
				-- Data write temporary register
				IF writePC='1' THEN
					data_write_tmp <= TG68_PC;
				ELSIF exec(writePC_add)='1' THEN
					data_write_tmp <= TG68_PC_add;
				elsif micro_state=trap00 THEN
					-- Stack frame format #2 support
					data_write_tmp <= exe_pc;
					useStackframe2<='1';
					writePCnext <= trap_trap OR trap_trapv OR exec(trap_chk) OR Z_error;
				elsif micro_state = trap0 then
					-- Stack frame format selection
					IF	useStackframe2='1' THEN
						-- Stack frame format #2
						data_write_tmp(15 downto 0) <= "0010" & trap_vector(11 downto 0);
					else
						-- Stack frame format #0
						data_write_tmp(15 downto 0) <= "0000" & trap_vector(11 downto 0);
						writePCnext <= trap_trap OR trap_trapv OR exec(trap_chk) OR Z_error;
					end if;
				ELSIF exec(hold_dwr)='1' THEN	
					-- Hold current value
					data_write_tmp <= data_write_tmp;
				ELSIF exec(exg)='1' THEN	
					-- Exchange registers
					data_write_tmp <= OP1out;
				ELSIF exec(get_ea_now)='1' AND ea_only='1' THEN
					-- PEA instruction
					data_write_tmp <= addr;
				ELSIF execOPC='1' THEN
					-- ALU result
					data_write_tmp <= ALUout;
				ELSIF (exec_DIRECT='1' AND state="10") THEN
					-- Direct data move
					data_write_tmp <= data_read;
					IF  exec(movepl)='1' THEN
						-- MOVEP long
						data_write_tmp(31 downto 8) <= data_write_tmp(23 downto 0);
					END IF;
				ELSIF exec(movepl)='1' THEN
					-- MOVEP from register
					data_write_tmp(15 downto 0) <= reg_QB(31 downto 16);
				ELSIF direct_data='1' THEN
					data_write_tmp <= last_data_read;
				ELSIF writeSR='1'THEN
					-- Write status register to stack
					data_write_tmp(15 downto 0) <= trap_SR(7 downto 0)& Flags(7 downto 0);
				ELSE	
					data_write_tmp <= OP2out;
				END IF;
			END IF;	
		END IF;	
	END PROCESS;
	
-----------------------------------------------------------------------------
-- Brief extension word handling - for 68020 addressing modes
-----------------------------------------------------------------------------
PROCESS (brief, OP1out, OP1outbrief, cpu)
	BEGIN
		-- Sign extend based on index size
		IF brief(11)='1' THEN
			OP1outbrief <= OP1out(31 downto 16);	-- Long index
		ELSE
			OP1outbrief <= (OTHERS=>OP1out(15));	-- Word index
		END IF;
		briefdata <= OP1outbrief&OP1out(15 downto 0);
		
		-- Scale factor for 68020+
		IF extAddr_Mode=1 OR (cpu(1)='1' AND extAddr_Mode=2) THEN
			CASE brief(10 downto 9) IS
				WHEN "00" => briefdata <= OP1outbrief&OP1out(15 downto 0);		-- *1
				WHEN "01" => briefdata <= OP1outbrief(14 downto 0)&OP1out(15 downto 0)&'0';		-- *2
				WHEN "10" => briefdata <= OP1outbrief(13 downto 0)&OP1out(15 downto 0)&"00";		-- *4
				WHEN "11" => briefdata <= OP1outbrief(12 downto 0)&OP1out(15 downto 0)&"000";		-- *8
				WHEN OTHERS => NULL;
			END CASE;
		END IF;
	END PROCESS;

-----------------------------------------------------------------------------
-- Memory address calculation
-----------------------------------------------------------------------------
PROCESS (clk, setdisp, memaddr_a, briefdata, memaddr_delta, setdispbyte, datatype, interrupt, rIPL_nr, IPL_vec,
         memaddr_reg, memaddr_delta_rega, memaddr_delta_regb, reg_QA, use_base, VBR, last_data_read, trap_vector, exec, set, cpu, use_VBR_Stackframe)
	BEGIN
		
		IF rising_edge(clk) THEN
			IF clkena_lw='1' THEN
				-- Initialize trap vector
				trap_vector(31 downto 10) <= (others => '0');
				
				-- Set trap vectors based on exception type
				IF trap_berr='1' THEN
					trap_vector(9 downto 0) <= "00" & X"08";		-- Bus error
				END IF;	
				IF trap_addr_error='1' THEN
					trap_vector(9 downto 0) <= "00" & X"0C";		-- Address error
				END IF;	
				IF trap_illegal='1' THEN
					trap_vector(9 downto 0) <= "00" & X"10";		-- Illegal instruction
				END IF;	
				IF set_Z_error='1' THEN
					trap_vector(9 downto 0) <= "00" & X"14";		-- Zero divide
				END IF;	
				IF exec(trap_chk)='1' THEN
					trap_vector(9 downto 0) <= "00" & X"18";		-- CHK instruction
				END IF;	
				IF trap_trapv='1' THEN
					trap_vector(9 downto 0) <= "00" & X"1C";		-- TRAPV instruction
				END IF;	
				IF trap_priv='1' THEN
					trap_vector(9 downto 0) <= "00" & X"20";		-- Privilege violation
				END IF;	
				IF trap_trace='1' THEN
					trap_vector(9 downto 0) <= "00" & X"24";		-- Trace
				END IF;	
				IF trap_1010='1' THEN
					trap_vector(9 downto 0) <= "00" & X"28";		-- Line 1010 emulator
				END IF;	
				IF trap_1111='1' THEN
					trap_vector(9 downto 0) <= "00" & X"2C";		-- Line 1111 emulator
				END IF;	
				IF trap_trap='1' THEN
					trap_vector(9 downto 0) <= "0010" & opcode(3 downto 0) & "00";		-- TRAP #n
				END IF;	
				IF trap_interrupt='1' or set_vectoraddr = '1' THEN
					trap_vector(9 downto 0) <= IPL_vec & "00";		-- Interrupt vector
				END IF;	
			END IF;
		END IF;
		
		-- Add VBR if enabled
		IF use_VBR_Stackframe='1' THEN
			trap_vector_vbr <= trap_vector+VBR;
		ELSE		
			trap_vector_vbr <= trap_vector;
		END IF;		
		
		-- Initialize memaddr_a with sign extension
		memaddr_a(4 downto 0) <= "00000";
		memaddr_a(7 downto 5) <= (OTHERS=>memaddr_a(4));
		memaddr_a(15 downto 8) <= (OTHERS=>memaddr_a(7));
		memaddr_a(31 downto 16) <= (OTHERS=>memaddr_a(15));
		
		-- Calculate displacement or offset
		IF setdisp='1' THEN
			IF exec(briefext)='1' THEN
				-- Brief extension with index
				memaddr_a <= briefdata+memaddr_delta;
			ELSIF setdispbyte='1' THEN
				-- 8-bit displacement
				memaddr_a(7 downto 0) <= last_data_read(7 downto 0);
			ELSE
				-- 16/32-bit displacement
				memaddr_a <= last_data_read;
			END IF;	 
		ELSIF set(presub)='1' THEN
			-- Pre-decrement adjustment
			IF set(longaktion)='1' THEN	
				memaddr_a(4 downto 0) <= "11100";		-- -4
			ELSIF datatype="00" AND set(use_SP)='0' THEN
				memaddr_a(4 downto 0) <= "11111";		-- -1
			ELSE
				memaddr_a(4 downto 0) <= "11110";		-- -2
			END IF;	
		ELSIF interrupt='1' THEN
			-- Interrupt autovector offset
			memaddr_a(4 downto 0) <= '1'&rIPL_nr&'0';	
		END IF;	 
		
		IF rising_edge(clk) THEN
			IF clkena_in='1' THEN
				-- Save PC for later restoration
				IF exec(get_2ndOPC)='1' OR (state="10" AND memread(0)='1') THEN
					tmp_TG68_PC <= addr;
				END IF;
				
				-- Memory address delta calculation
				use_base <= '0'; 
				memaddr_delta_regb <= (others => '0');
				
				IF memmaskmux(3)='0' OR exec(mem_addsub)='1' THEN
					-- Use ALU result for address calculation
					memaddr_delta_rega <= addsub_q;
				ELSIF set(restore_ADDR)='1' THEN
					-- Restore saved PC
					memaddr_delta_rega <= tmp_TG68_PC;
				ELSIF exec(direct_delta)='1' THEN
					-- Direct data as delta
					memaddr_delta_rega <= data_read;
				ELSIF exec(ea_to_pc)='1' AND setstate="00" THEN
					-- Jump/JSR address
					memaddr_delta_rega <= addr;
				ELSIF set(addrlong)='1' THEN
					-- Long word address
					memaddr_delta_rega <= last_data_read;
				ELSIF setstate="00" THEN
					-- PC relative
					memaddr_delta_rega <= TG68_PC_add;
				ELSIF exec(dispouter)='1' THEN
					-- Outer displacement (68020)
					memaddr_delta_rega <= ea_data;
					memaddr_delta_regb <= memaddr_a;
				ELSIF set_vectoraddr='1' THEN
					-- Exception vector
					memaddr_delta_rega <= trap_vector_vbr;
				ELSE 
					memaddr_delta_rega <= memaddr_a;
					IF interrupt='0' AND Suppress_Base='0' THEN
						use_base <= '1';	-- Use base register
					END IF;	
				END IF;
					
				-- MOVEM address update
				if ((memread(0) = '1') and state(1) = '1') or movem_presub = '0' then
					memaddr <= addr;
				END IF;
			END IF;
		END IF;

		-- Final address calculation
		memaddr_delta <= memaddr_delta_rega + memaddr_delta_regb;
		addr <= memaddr_reg+memaddr_delta;
		addr_out <= memaddr_reg + memaddr_delta;

		-- Select base register or zero
		IF use_base='0' THEN
			memaddr_reg <= (others=>'0');
		ELSE	
			memaddr_reg <= reg_QA;
		END IF;	
    END PROCESS;
    
-----------------------------------------------------------------------------
-- PC Calculation and opcode fetch control
-----------------------------------------------------------------------------
PROCESS (clk, IPL, setstate, addrvalue, state, exec_write_back, set_direct_data, next_micro_state, stop, make_trace, make_berr, IPL_nr, FlagsSR, set_rot_cnt, opcode, writePCbig, set_exec, exec,
        PC_dataa, PC_datab, setnextpass, last_data_read, TG68_PC_brw, TG68_PC_word, Z_error, trap_trap, trap_trapv, interrupt, tmp_TG68_PC, TG68_PC, use_VBR_Stackframe, writePCnext)
	BEGIN
	
		-- PC operand A selection
		PC_dataa <= TG68_PC;
		IF TG68_PC_brw = '1' THEN
			PC_dataa <= tmp_TG68_PC;
		END IF;
		
		-- PC operand B calculation with sign extension
		PC_datab(2 downto 0) <= (others => '0');
		PC_datab(3) <= PC_datab(2);
		PC_datab(7 downto 4) <= (others => PC_datab(3));
		PC_datab(15 downto 8) <= (others => PC_datab(7));
		PC_datab(31 downto 16) <= (others => PC_datab(15));
		
		-- Interrupt stack frame adjustment
		IF interrupt='1' THEN
			PC_datab(2 downto 1) <= "11";	-- +6 for interrupt
		END IF;
		
		-- PC increment control
		IF exec(writePC_add) ='1' THEN
			IF writePCbig='1' THEN
				PC_datab(3) <= '1';		-- +8
				PC_datab(1) <= '1';
			ELSE	
				PC_datab(2) <= '1';		-- +4
			END IF;
			-- Additional increment for certain traps
			IF (use_VBR_Stackframe='0' AND (trap_trap='1' OR trap_trapv='1' OR exec(trap_chk)='1' OR Z_error='1')) OR writePCnext='1' THEN
				PC_datab(1) <= '1';		-- +2 more
			END IF;
		ELSIF state="00" THEN
			PC_datab(1) <= '1';			-- Normal +2
		END IF;	
		
		-- Branch displacement
		IF TG68_PC_brw = '1' THEN	
			IF TG68_PC_word='1' THEN
				PC_datab <= last_data_read;		-- Word/long displacement
			ELSE
				PC_datab(7 downto 0) <= opcode(7 downto 0);	-- Byte displacement
			END IF;
		END IF;

		-- PC addition
		TG68_PC_add <= PC_dataa+PC_datab;
		
		-- Opcode fetch control
		setopcode <= '0';
		setendOPC <= '0';
		setinterrupt <= '0';
		
		-- Check for instruction completion and interrupt
		IF setstate="00" AND next_micro_state=idle AND setnextpass='0' AND (exec_write_back='0' OR state="11") AND set_rot_cnt="000001" AND set_exec(opcCHK)='0'THEN
			setendOPC <= '1';
			-- Check for pending interrupt or trace
			IF FlagsSR(2 downto 0)<IPL_nr OR IPL_nr="111"  OR make_trace='1' OR make_berr='1' THEN
				setinterrupt <= '1';
			ELSIF stop='0' THEN
				setopcode <= '1';		-- Fetch next opcode
			END IF;
		END IF;	
		
		-- Execute opcode control
		setexecOPC <= '0';
		IF setstate="00" AND next_micro_state=idle AND set_direct_data='0' AND (exec_write_back='0' OR (state="10" AND addrvalue='0')) THEN
			setexecOPC <= '1';
		END IF;
		
		-- Invert IPL for active low signals
		IPL_nr <= NOT IPL;
		
		IF rising_edge(clk) THEN
			IF Reset = '1' THEN
				-- Initialize CPU state
				state <= "01";
				addrvalue <= '0';
				opcode <= X"2E79"; 				-- move $0,a7 (stack init)
				trap_interrupt <= '0';
				interrupt <= '0';
				last_opc_read  <= X"4EF9";		-- jmp nn.l
				TG68_PC <= X"00000004";		-- Start at vector 1
				decodeOPC <= '0';
				endOPC <= '0';
				TG68_PC_word <= '0';
				execOPC <= '0';
				stop <= '0';
				rot_cnt <="000001";
				trap_trace <= '0';
				trap_berr <= '0';
				writePCbig <= '0';
				Suppress_Base <= '0'; 
				make_berr <= '0';
				memmask <= "111111";
				exec_write_back <= '0';
			ELSE
				IF clkena_in='1' THEN
					-- Shift memory mask for multi-cycle operations
					memmask <= memmask(3 downto 0)&"11";
					memread <= memread(1 downto 0)&memmaskmux(5 downto 4);
					
					-- PC update
					IF exec(directPC)='1' THEN
						TG68_PC <= data_read;		-- RTS/RTD
					ELSIF exec(ea_to_pc)='1' THEN
						TG68_PC <= addr;			-- JMP/JSR
					ELSIF (state ="00" OR TG68_PC_brw = '1') AND stop='0'  THEN				
						TG68_PC <= TG68_PC_add;	-- Normal increment or branch
					END IF;	
				END IF;	
				
				IF clkena_lw='1' THEN
					-- Control signal updates
					interrupt <= setinterrupt;
					decodeOPC <= setopcode;
					endOPC <= setendOPC;
					execOPC <= setexecOPC;
					
					exe_datatype <= set_datatype;
					exe_opcode <= opcode;

					-- Bus error handling
					if(trap_berr='0') then
						make_berr <= (berr OR make_berr);
					else
						make_berr <= '0';
					end if;
						
					-- STOP instruction handling
					stop <= set_stop OR (stop AND NOT setinterrupt);
					
					-- Interrupt processing
					IF setinterrupt='1' THEN
						trap_interrupt <= '0';
						trap_trace <= '0';
						make_berr <= '0';
						trap_berr <= '0';
						IF make_trace='1' THEN
							trap_trace <= '1';
						ELSIF make_berr='1' THEN
							trap_berr <= '1';
						ELSE	
							rIPL_nr <= IPL_nr;
							IPL_vec <= "00011"&IPL_nr;		-- Default autovector
							trap_interrupt <= '1';
						END IF;
					END IF;	
					
					-- Non-autovectored interrupt vector fetch
					IF micro_state=trap0 AND IPL_autovector='0' THEN 			
						IPL_vec <= last_data_read(7 downto 0);
					END IF;	
					
					-- Save last opcode for rerun
					IF state="00" THEN				
						last_opc_read <= data_read(15 downto 0);
						last_opc_pc <= tg68_pc;
					END IF;	
					
					-- Opcode decode setup
					IF setopcode='1' THEN
						trap_interrupt <= '0';
						trap_trace <= '0';
						TG68_PC_word <= '0';
						trap_berr <= '0';
					ELSIF opcode(7 downto 0)="00000000" OR opcode(7 downto 0)="11111111" OR data_is_source='1' THEN
						TG68_PC_word <= '1';		-- Next fetch is extension word
					END IF;	
					
					-- Bit field parameters
					IF exec(get_bfoffset)='1' THEN
						alu_width <= bf_width;
						alu_bf_shift <= bf_shift;
						alu_bf_loffset <= bf_loffset;
						alu_bf_ffo_offset <= bf_full_offset+bf_width+1;
					END IF;
					
					-- Memory read control
					memread <= "1111";
					
					-- Function code generation
					FC(1) <= NOT setstate(1) OR (PCbase AND NOT setstate(0));
					FC(0) <= setstate(1) AND (NOT PCbase OR setstate(0));
					IF interrupt='1' THEN
						FC(1 downto 0) <= "11";		-- Interrupt acknowledge
					END IF;	
					
					-- Write-back control
					IF state="11" THEN
						exec_write_back <= '0';
					ELSIF setstate="10" AND setaddrvalue='0' AND write_back='1' THEN
						exec_write_back <= '1';
					END IF;	
					
					-- State machine control
					IF (state="10" AND addrvalue='0' AND write_back='1' AND setstate/="10") OR set_rot_cnt/="000001" OR (stop='1' AND interrupt='0') OR set_exec(opcCHK)='1' THEN
						state <= "01";		-- Idle state
						memmask <= "111111";
						addrvalue <= '0';
					ELSIF execOPC='1' AND exec_write_back='1' THEN
						state <= "11";		-- Write state
						FC(1 downto 0) <= "01";	-- Data space
						memmask <= wbmemmask;
						addrvalue <= '0';
					ELSE	
						state <= setstate;
						addrvalue <= setaddrvalue; 
						
						-- Memory mask setup for different access types
						IF setstate="01" THEN
							memmask <= "111111";
							wbmemmask <= "111111";
						ELSIF exec(get_bfoffset)='1' THEN
							memmask <= set_memmask;
							wbmemmask <= set_memmask;
							oddout <= set_oddout;
						ELSIF set(longaktion)='1' THEN
							memmask <= "100001";		-- Long word
							wbmemmask <= "100001";
							oddout <= '0';
						ELSIF set_datatype="00" AND setstate(1)='1' THEN	
							memmask <= "101111";		-- Byte
							wbmemmask <= "101111";
							IF set(mem_byte)='1' THEN
								oddout <= '0';
							ELSE
								oddout <= '1';
							END IF;	
						ELSE	
							memmask <= "100111";		-- Word
							wbmemmask <= "100111";
							oddout <= '0';
						END IF;	
					END IF;

					-- Rotation counter control
					IF decodeOPC='1' THEN
						rot_bits <= set_rot_bits;
						writePCbig <= '0';
					ELSE	
						writePCbig <= set_writePCbig OR writePCbig; 
					END IF;
					IF decodeOPC='1' OR exec(ld_rot_cnt)='1' OR rot_cnt/="000001" THEN
						rot_cnt <= set_rot_cnt;
					END IF;
					
					-- Base suppression control
					IF set_Suppress_Base='1' THEN
						Suppress_Base <= '1';
					ELSIF setstate(1)='1' OR (ea_only='1' AND set(get_ea_now)='1') THEN	
						Suppress_Base <= '0';
					END IF;
					
					-- Brief extension word capture
					IF getbrief='1' THEN
						IF state(1)='1' THEN
							brief <= last_opc_read(15 downto 0);
						ELSE
							brief <= data_read(15 downto 0);
						END IF;
					END IF;	
					
					-- Opcode selection
					IF setopcode='1' AND berr='0' THEN
						IF state="00" THEN
							opcode <= data_read(15 downto 0);
							exe_pc <= tg68_pc;
						ELSE
							opcode <= last_opc_read(15 downto 0);
							exe_pc <= last_opc_pc;
						END IF;
						nextpass <= '0';
					ELSIF setinterrupt='1' OR setopcode='1' THEN
						opcode <= X"4E71";		-- NOP for interrupt
						nextpass <= '0';
					ELSE
						IF setnextpass='1' OR regdirectsource='1' THEN
							nextpass <= '1';	
						END IF;
					END IF;

					-- Save trap SR
					IF decodeOPC='1' OR interrupt='1' THEN
						trap_SR <= FlagsSR;
					END IF;
				END IF;	
			END IF;	
		END IF;	
	
		-- PC base control
		IF rising_edge(clk) THEN
			IF Reset = '1' THEN
				PCbase <= '1';
			ELSIF clkena_lw='1' THEN
				PCbase <= set_PCbase OR PCbase;
				IF setexecOPC='1' OR (state(1)='1' AND movem_run='0') THEN
					PCbase <= '0';
				END IF;	
			END IF;	
			
			-- Execution control transfer
			IF clkena_lw='1' THEN
				exec <= set;
				exec(alu_move) <= set(opcMOVE) OR set(alu_move);
				exec(alu_setFlags) <= set(opcADD) OR set(alu_setFlags);
				exec_tas <= '0';
				exec(subidx) <= set(presub) or set(subidx);
				IF setexecOPC='1' THEN
					exec <= set_exec OR set;
					exec(alu_move) <= set_exec(opcMOVE) OR set(opcMOVE) OR set(alu_move);
					exec(alu_setFlags) <= set_exec(opcADD) OR set(opcADD) OR set(alu_setFlags);
					exec_tas <= set_exec_tas;
				END IF;	
				exec(get_2ndOPC) <= set(get_2ndOPC) OR setopcode;
			END IF;	
		END IF;	
	END PROCESS;
	
------------------------------------------------------------------------------
-- Prepare Bitfield Parameters - 68020 bit field instructions
------------------------------------------------------------------------------		
PROCESS (clk, Reset, sndOPC, reg_QA, reg_QB, bf_width, bf_offset, bf_bhits, opcode, setstate, bf_shift)
	BEGIN
		-- Bit field offset source
		IF sndOPC(11)='1' THEN
			bf_offset <= '0'&reg_QA(4 downto 0);	-- Register
		ELSE
			bf_offset <= '0'&sndOPC(10 downto 6);	-- Immediate
		END IF;	
		IF sndOPC(11)='1' THEN
			bf_full_offset <= reg_QA;
		ELSE
			bf_full_offset <= (others => '0');
			bf_full_offset(4 downto 0) <= sndOPC(10 downto 6);
		END IF;	
		
		-- Bit field width (0 means 32)
		bf_width(5) <= '0';
		IF sndOPC(5)='1' THEN
			bf_width(4 downto 0) <= reg_QB(4 downto 0)-1;	-- Register
		ELSE
			bf_width(4 downto 0) <= sndOPC(4 downto 0)-1;	-- Immediate
		END IF;	
		
		-- Calculate bit field boundaries
		bf_bhits <= bf_width+bf_offset;
		set_oddout <= NOT bf_bhits(3);
		
		-- Calculate shift amounts
		IF opcode(10 downto 8)="111" THEN --BFINS
			bf_loffset <= 32-bf_shift;
		ELSE
			bf_loffset <= bf_shift;
		END IF;
		bf_loffset(5) <= '0';
		
		-- Memory vs register bit field
		IF opcode(4 downto 3)="00" THEN	-- Register
			IF opcode(10 downto 8)="111" THEN --BFINS
				bf_shift <= bf_bhits+1;
			ELSE
				bf_shift <= 31-bf_bhits;
			END IF;
			bf_shift(5) <= '0';
		ELSE	-- Memory
			IF opcode(10 downto 8)="111" THEN --BFINS
				bf_shift <= "011001"+("000"&bf_bhits(2 downto 0));
				bf_shift(5) <= '0';
			ELSE
				bf_shift <= "000"&("111"-bf_bhits(2 downto 0));
			END IF;
			bf_offset(4 downto 3) <= "00";
		END IF;
		
		-- Memory access size based on bit field size
		CASE bf_bhits(5 downto 3) IS
			WHEN "000" =>
				set_memmask <= "101111";	-- Byte
			WHEN "001" =>
				set_memmask <= "100111";	-- Word
			WHEN "010" =>
				set_memmask <= "100011";	-- 3 bytes
			WHEN "011" =>
				set_memmask <= "100001";	-- Long
			WHEN OTHERS =>
				set_memmask <= "100000";	-- 5 bytes
		END CASE;	
		IF setstate="00" THEN
			set_memmask <= "100111";		-- Default word
		END IF;
	END PROCESS;		
	
------------------------------------------------------------------------------
-- Status Register operations
------------------------------------------------------------------------------		
PROCESS (clk, Reset, FlagsSR, last_data_read, OP2out, exec)
	BEGIN
		-- SR operation input selection
		IF exec(andiSR)='1' THEN
			SRin <= FlagsSR AND last_data_read(15 downto 8);
		ELSIF exec(eoriSR)='1' THEN
			SRin <= FlagsSR XOR last_data_read(15 downto 8);
		ELSIF exec(oriSR)='1' THEN
			SRin <= FlagsSR OR last_data_read(15 downto 8);
		ELSE	
			SRin <= OP2out(15 downto 8);
		END IF;	
		
		IF rising_edge(clk) THEN
			IF Reset='1' THEN
				-- Initialize in supervisor mode with interrupts disabled
				FC(2) <= '1';
				SVmode <= '1';
				preSVmode <= '1';
				FlagsSR <= "00100111";		-- S=1, IPL=7
				make_trace <= '0';
			ELSIF clkena_lw = '1' THEN
				-- Trace flag handling
				IF setopcode='1' THEN
					make_trace <= FlagsSR(7);
					IF set(changeMode)='1' THEN
						SVmode <= NOT SVmode; 
					ELSE
						SVmode <= preSVmode;
					END IF;	
				END IF;
				
				-- Clear trace on exceptions
				IF trap_berr='1' OR trap_illegal='1' OR trap_addr_error='1' OR trap_priv='1' OR trap_1010='1' OR trap_1111='1' THEN
					make_trace <= '0';
					FlagsSR(7) <= '0';
				END IF;
				
				-- Mode change handling
				IF set(changeMode)='1' THEN
					preSVmode <= NOT preSVmode;
					FlagsSR(5) <= NOT preSVmode;
					FC(2) <= NOT preSVmode;
				END IF;
				
				-- Clear trace after trap
				IF micro_state=trap3 THEN
					FlagsSR(7) <= '0';
				END IF;
				IF trap_trace='1' AND state="10" THEN
					make_trace <= '0';
				END IF;
				
				-- Direct SR updates
				IF exec(directSR)='1' OR set_stop='1' THEN
					FlagsSR <= data_read(15 downto 8);
				END IF;	
				
				-- Interrupt priority update
				IF interrupt='1' AND trap_interrupt='1' THEN
					FlagsSR(2 downto 0) <=rIPL_nr;
				END IF;	
				
				-- SR write operations
				IF exec(to_SR)='1' THEN
					FlagsSR(7 downto 0) <= SRin;
					FC(2) <= SRin(5);
				ELSIF exec(update_FC)='1' THEN
					FC(2) <= FlagsSR(5);
				END IF;
				
				-- Force supervisor for interrupts
				IF interrupt='1' THEN
					FC(2) <= '1';
				END IF;	
				
				-- Clear unused bits for 68000
				IF cpu(1)='0' THEN
					FlagsSR(4) <= '0';		-- M flag
					FlagsSR(6) <= '0';		-- Unused
				END IF;
				FlagsSR(3) <= '0';			-- Always zero
			END IF;
		END IF;	
	END PROCESS;

-----------------------------------------------------------------------------
-- Main instruction decode - this is the heart of the CPU
-----------------------------------------------------------------------------
PROCESS (clk, cpu, OP1out, OP2out, opcode, exe_condition, nextpass, micro_state, decodeOPC, state, setexecOPC, Flags, FlagsSR, direct_data, build_logical,
		 build_bcd, set_Z_error, trapd, movem_run, last_data_read, set, set_V_Flag, z_error, trap_trace, trap_interrupt,
		 SVmode, preSVmode, stop, long_done, ea_only, setstate, addrvalue, execOPC, exec_write_back, exe_datatype,
		 datatype, interrupt, c_out, trapmake, rot_cnt, brief, addr, trap_trapv, last_data_in, use_VBR_Stackframe,
		 long_start, set_datatype, sndOPC, set_exec, exec, ea_build_now, reg_QA, reg_QB, make_berr, trap_berr)
	BEGIN
		-- Initialize all control signals to defaults
		TG68_PC_brw <= '0';	
		setstate <= "00";
		setaddrvalue <= '0';
		Regwrena_now <= '0';
		movem_presub <= '0';
		setnextpass <= '0';
		regdirectsource <= '0';
		setdisp <= '0';
		setdispbyte <= '0';
		getbrief <= '0';
		dest_LDRareg <= '0';
		dest_areg <= '0';
		source_areg <= '0';
		data_is_source <= '0';
		write_back <= '0';
		setstackaddr <= '0';
		writePC <= '0';
		ea_build_now <= '0';
		set_rot_bits <= opcode(4 downto 3);
		set_rot_cnt <= "000001";
		dest_hbits <= '0';
		source_lowbits <= '0';
		source_LDRLbits <= '0';
		source_LDRMbits <= '0';
		source_2ndHbits <= '0';
		source_2ndMbits <= '0';
		source_2ndLbits <= '0';
		dest_LDRHbits <= '0';
		dest_LDRLbits <= '0';
		dest_2ndHbits <= '0';
		dest_2ndLbits <= '0';
		ea_only <= '0';
		set_direct_data <= '0';
		set_exec_tas <= '0';
		trap_illegal <='0';
		trap_addr_error <= '0';
		trap_priv <='0';
		trap_1010 <='0';
		trap_1111 <='0';
		trap_trap <='0';
		trap_trapv <= '0';
		trapmake <='0';
		set_vectoraddr <='0';
		writeSR <= '0';
		set_stop <= '0';
		set_Z_error <= '0';
		check_aligned <='0';

		next_micro_state <= idle;
		build_logical <= '0';
		build_bcd <= '0';
		skipFetch <= make_berr;
		set_writePCbig <= '0';
		set_Suppress_Base <= '0';
		set_PCbase <= '0';
						
		-- Decrement rotation counter
		IF rot_cnt/="000001" THEN
			set_rot_cnt <= rot_cnt-1;
		END IF;	
		set_datatype <= datatype;
		
		-- Clear all microcode bits
		set <= (OTHERS=>'0');
		set_exec <= (OTHERS=>'0');
		set(update_ld) <= '0';
		
------------------------------------------------------------------------------
-- Source operand size determination
------------------------------------------------------------------------------		
		CASE opcode(7 downto 6) IS
			WHEN "00" => datatype <= "00";		-- Byte
			WHEN "01" => datatype <= "01";		-- Word
			WHEN OTHERS => datatype <= "10";	-- Long
		END CASE;

		-- Restore address for write-back operations
		IF execOPC='1' AND exec_write_back='1' THEN
			set(restore_ADDR) <= '1';
		END IF;
		
		-- Bus error trap handling
		IF interrupt='1' AND trap_berr='1' THEN
			next_micro_state <= trap0;
			IF preSVmode='0' THEN
				set(changeMode) <= '1';
			END IF;
			setstate <= "01";
		END IF;	
		
		-- General trap handling
		IF trapmake='1' AND trapd='0' THEN
			IF cpu(1)='1' AND (trap_trapv='1' OR set_Z_error='1' OR exec(trap_chk)='1') THEN
				next_micro_state <= trap00;		-- Format #2 for 68010+
			else
				next_micro_state <= trap0;
			end if;
			IF use_VBR_Stackframe='0' THEN
				set(writePC_add) <= '1';
			END IF;
			IF preSVmode='0' THEN
				set(changeMode) <= '1';
			END IF;
			setstate <= "01";
		END IF;	
		
		-- Trace trap handling
		IF micro_state=int1 OR (interrupt='1' AND trap_trace='1') THEN
			if trap_trace='1' AND cpu(1) = '1' then
				next_micro_state <= trap00;		-- Format #2 for trace
			else
				next_micro_state <= trap0;
			end if;
			IF preSVmode='0' THEN
				set(changeMode) <= '1';
			END IF;
			setstate <= "01";
		END IF;	
	
		-- Mode change check
		IF setexecOPC='1' AND FlagsSR(5)/=preSVmode THEN
			set(changeMode) <= '1';
		END IF;

		-- Interrupt acknowledge cycle
		IF interrupt='1' AND trap_interrupt='1'THEN
			next_micro_state <= int1;
			set(update_ld) <= '1';
			setstate <= "10";
		END IF;
			
		-- User/Supervisor stack pointer swap
		IF set(changeMode)='1' THEN		
			set(to_USP) <= '1';
			set(from_USP) <= '1';
			setstackaddr <='1';
		END IF;
			
		-- Effective address read setup
		IF ea_only='0' AND set(get_ea_now)='1' THEN
			setstate <= "10";
		END IF;

		-- Long operation setup
		IF setstate(1)='1' AND set_datatype(1)='1' THEN
			set(longaktion) <= '1';
		END IF;

		-- Effective address calculation
		IF (ea_build_now='1' AND decodeOPC='1') OR exec(ea_build)='1' THEN
			CASE opcode(5 downto 3) IS		-- Source EA mode
				WHEN "010"|"011"|"100" =>						-- (An), (An)+, -(An)
					set(get_ea_now) <='1';
					setnextpass <= '1';
					IF opcode(3)='1' THEN	-- (An)+
						set(postadd) <= '1';
						IF opcode(2 downto 0)="111" THEN
							set(use_SP) <= '1';
						END IF;
					END IF;	 	
					IF opcode(5)='1' THEN	-- -(An)
						set(presub) <= '1'; 					
						IF opcode(2 downto 0)="111" THEN
							set(use_SP) <= '1';
						END IF;
					END IF;	 	
				WHEN "101" =>				-- (d16,An)
					next_micro_state <= ld_dAn1;
				WHEN "110" =>				-- (d8,An,Xn)
					next_micro_state <= ld_AnXn1;
					getbrief <='1';
				WHEN "111" =>
					CASE opcode(2 downto 0) IS
						WHEN "000" =>				-- (xxxx).W
							next_micro_state <= ld_nn;
						WHEN "001" =>				-- (xxxx).L
							set(longaktion) <= '1';
							next_micro_state <= ld_nn;
						WHEN "010" =>				-- (d16,PC)
							next_micro_state <= ld_dAn1;
							set(dispouter) <= '1';
							set_Suppress_Base <= '1';
							set_PCbase <= '1';
						WHEN "011" =>				-- (d8,PC,Xn)
							next_micro_state <= ld_AnXn1;
							getbrief <= '1';
							set(dispouter) <= '1';
							set_Suppress_Base <= '1';
							set_PCbase <= '1';
						WHEN "100" =>				-- #data (immediate)
							setnextpass <= '1';
							set_direct_data <= '1';
							IF datatype="10" THEN
								set(longaktion) <= '1';
							END IF;
						WHEN OTHERS => NULL;
					END CASE;
				WHEN OTHERS => NULL;
			END CASE;
		END IF;
		
------------------------------------------------------------------------------
-- Main opcode decode - organized by first nibble
------------------------------------------------------------------------------
		CASE opcode(15 downto 12) IS
-- 0000 - Bit operations, immediate ops -------------------------------------
			WHEN "0000" =>
			IF opcode(8)='1' AND opcode(5 downto 3)="001" THEN -- MOVEP
				datatype <= "00";				-- Byte transfers
				set(use_SP) <= '1';				-- Uses stack pointer
				set(no_Flags) <='1';
				IF opcode(7)='0' THEN  -- Memory to register
					set_exec(Regwrena) <= '1';
					set_exec(opcMOVE) <= '1';
					set(movepl) <= '1';
				END IF;
				IF decodeOPC='1' THEN
					IF opcode(6)='1' THEN		-- Long operation
						set(movepl) <= '1';
					END IF;
					IF opcode(7)='0' THEN
						set_direct_data <= '1';		-- To register
					END IF;
					next_micro_state <= movep1;
				END IF;
				IF setexecOPC='1' THEN
					dest_hbits <='1';
				END IF;
			ELSE
				IF opcode(8)='1' OR opcode(11 downto 9)="100" THEN		-- Dynamic bit operations
					IF opcode(5 downto 3)/="001" AND -- An not allowed
					   (opcode(8 downto 3)/="000111" OR opcode(2)='0') AND -- BTST static restrictions
					   (opcode(8 downto 2)/="1001111" OR opcode(1 downto 0)="00") AND -- BTST dynamic restrictions
					   (opcode(7 downto 6)="00" OR opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00") THEN -- BCHG/BCLR/BSET restrictions
						set_exec(opcBITS) <= '1';
						set_exec(ea_data_OP1) <= '1';
						IF opcode(7 downto 6)/="00" THEN		-- Not BTST
							IF opcode(5 downto 4)="00" THEN
								set_exec(Regwrena) <= '1';
							END IF;
							write_back <= '1';
						END IF;
						IF opcode(5 downto 4)="00" THEN
							datatype <= "10";			-- Long for register
						ELSE
							datatype <= "00";			-- Byte for memory
						END IF;
						IF opcode(8)='0' THEN			-- Static bit number
							IF decodeOPC='1' THEN
								next_micro_state <= nop;
								set(get_2ndOPC) <= '1';
								set(ea_build) <= '1';
							END IF;
						ELSE							-- Dynamic bit number
							ea_build_now <= '1';
						END IF;
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				ELSIF opcode(8 downto 6)="011" THEN			-- CAS/CAS2/CMP2/CHK2 (68020+)
					IF cpu(1)='1' THEN
						IF opcode(11)='1' THEN					-- CAS/CAS2
							IF (opcode(10 downto 9)/="00" AND -- Size must be valid
							   opcode(5 downto 4)/="00" AND (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00")) OR -- EA restrictions
							   (opcode(10)='1' AND opcode(5 downto 0)="111100") THEN -- CAS2 special encoding
								CASE opcode(10 downto 9) IS
									WHEN "01" => datatype <= "00";		-- Byte
									WHEN "10" => datatype <= "01";		-- Word
									WHEN OTHERS => datatype <= "10";	-- Long
								END CASE;
								IF opcode(10)='1' AND opcode(5 downto 0)="111100" THEN -- CAS2
									IF decodeOPC='1' THEN
										set(get_2ndOPC) <= '1';
										next_micro_state <= cas21;
									END IF;
								ELSE											-- CAS
									IF decodeOPC='1' THEN
										next_micro_state <= nop;
										set(get_2ndOPC) <= '1';
										set(ea_build) <= '1';
									END IF;
									IF micro_state=idle AND nextpass='1' THEN
										source_2ndLbits <= '1';
										set(ea_data_OP1) <= '1';
										set(addsub) <= '1';
										set(alu_exec) <= '1';
										set(alu_setFlags) <= '1';
										setstate <= "01";
										next_micro_state <= cas1;
									END IF;
								END IF;
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						ELSE				-- CMP2/CHK2
							IF opcode(10 downto 9)/="11" AND -- Valid size
							   opcode(5 downto 4)/="00" AND opcode(5 downto 3)/="011" AND opcode(5 downto 3)/="100" AND opcode(5 downto 2)/="1111" THEN -- EA restrictions
								set(trap_chk) <= '1';
								datatype <= opcode(10 downto 9);
								IF decodeOPC='1' THEN
									next_micro_state <= nop;
									set(get_2ndOPC) <= '1';
									set(ea_build) <= '1';
								END IF;
								IF set(get_ea_now)='1' THEN
									set(mem_addsub) <= '1';
									set(OP1addr) <= '1';
								END IF;
								IF micro_state=idle AND nextpass='1' THEN
									setstate <= "10";
									set(hold_OP2) <='1';
									IF exe_datatype/="00" THEN
										check_aligned <='1';
									END IF;
									next_micro_state <= chk20;
								END IF;
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						END IF;
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				ELSIF opcode(11 downto 9)="111" THEN		-- MOVES (68010+)
					IF cpu(0)='1' AND opcode(7 downto 6)/="11" AND opcode(5 downto 4)/="00" AND (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00") THEN
						IF SVmode='1' THEN
							-- TODO: implement MOVES
							trap_illegal <= '1';
							trapmake <= '1';
						ELSE
							trap_priv <= '1';
							trapmake <= '1';
						END IF;
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				ELSE								-- Immediate operations (ANDI, ORI, etc.)
					IF opcode(7 downto 6)/="11" AND opcode(5 downto 3)/="001" THEN -- An not allowed
						-- Decode immediate operation type
						IF opcode(11 downto 9)="000" THEN	-- ORI
							IF opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00" OR (opcode(2 downto 0)="100" AND opcode(7)='0') THEN
								set_exec(opcOR) <= '1';
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						END IF;
						IF opcode(11 downto 9)="001" THEN	-- ANDI
							IF opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00" OR (opcode(2 downto 0)="100" AND opcode(7)='0') THEN
								set_exec(opcAND) <= '1';
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						END IF;
						IF opcode(11 downto 9)="010" OR opcode(11 downto 9)="011" THEN	-- SUBI, ADDI
							IF opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00" THEN
								set_exec(opcADD) <= '1';
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						END IF;
						IF opcode(11 downto 9)="101" THEN	-- EORI
							IF opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00" OR (opcode(2 downto 0)="100" AND opcode(7)='0') THEN
								set_exec(opcEOR) <= '1';
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						END IF;
						IF opcode(11 downto 9)="110" THEN	-- CMPI
							IF opcode(5 downto 3)/="111" OR opcode(2)='0' THEN
								set_exec(opcCMP) <= '1';
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						END IF;
						IF (set_exec(opcor) OR set_exec(opcand) OR set_exec(opcADD) OR set_exec(opcEor) OR set_exec(opcCMP))='1' THEN
							IF opcode(7)='0' AND opcode(5 downto 0)="111100" AND (set_exec(opcAND) OR set_exec(opcOR) OR set_exec(opcEOR))='1' THEN		-- to CCR/SR
								IF decodeOPC='1' AND SVmode='0' AND opcode(6)='1' THEN  -- to SR needs privilege
									trap_priv <= '1';
									trapmake <= '1';
								ELSE
									set(no_Flags) <= '1';
									IF decodeOPC='1' THEN
										IF opcode(6)='1' THEN
											set(to_SR) <= '1';
										END IF;
										set(to_CCR) <= '1';
										set(andiSR) <= set_exec(opcAND);
										set(eoriSR) <= set_exec(opcEOR);
										set(oriSR) <= set_exec(opcOR);
										setstate <= "01";
										next_micro_state <= nopnop;
									END IF;
								END IF;
							ELSIF opcode(7)='0' OR opcode(5 downto 0)/="111100" OR (set_exec(opcand) OR set_exec(opcor) OR set_exec(opcEor))='0' THEN
								-- Normal immediate operation
								IF decodeOPC='1' THEN
									next_micro_state <= andi;
									set(get_2ndOPC) <='1';
									set(ea_build) <= '1';
									set_direct_data <= '1';
									IF datatype="10" THEN
										set(longaktion) <= '1';
									END IF;
								END IF;
								IF opcode(5 downto 4)/="00" THEN
									set_exec(ea_data_OP1) <= '1';
								END IF;
								IF opcode(11 downto 9)/="110" THEN	-- Not CMPI
									IF opcode(5 downto 4)="00" THEN
										set_exec(Regwrena) <= '1';
									END IF;
									write_back <= '1';
								END IF;
								IF opcode(10 downto 9)="10" THEN	-- CMPI, SUBI need subtract
									set(addsub) <= '1';
								END IF;
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						ELSE
							trap_illegal <= '1';
							trapmake <= '1';
						END IF;
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				END IF;
			END IF;
				
-- 0001, 0010, 0011 - MOVE operations ----------------------------------------
			WHEN "0001"|"0010"|"0011" =>				-- MOVE.B, MOVE.L, MOVE.W
				IF ((opcode(11 downto 10)="00" OR opcode(8 downto 6)/="111") AND -- Destination EA check
				   (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00") AND -- Source EA check
				   (opcode(13)='1' OR (opcode(8 downto 6)/="001" AND opcode(5 downto 3)/="001"))) THEN -- Byte An restrictions
					set_exec(opcMOVE) <= '1';
					ea_build_now <= '1';
					IF opcode(8 downto 6)="001" THEN		-- MOVEA
						set(no_Flags) <= '1';
					END IF;
					IF opcode(5 downto 4)="00" THEN		-- Dn/An source
						IF opcode(8 downto 7)="00" THEN
							set_exec(Regwrena) <= '1';
						END IF;
					END IF;
					-- Set operation size
					CASE opcode(13 downto 12) IS
						WHEN "01" => datatype <= "00";		-- Byte
						WHEN "10" => datatype <= "10";		-- Long
						WHEN OTHERS => datatype <= "01";	-- Word
					END CASE;
					source_lowbits <= '1';					
					IF opcode(3)='1' THEN
						source_areg <= '1';					-- An source
					END IF;

					IF nextpass='1' OR opcode(5 downto 4)="00" THEN
						dest_hbits <= '1';
						IF opcode(8 downto 6)/="000" THEN
							dest_areg <= '1';				-- An destination
						END IF;
					END IF;

					-- Destination EA calculation
					IF micro_state=idle AND (nextpass='1' OR (opcode(5 downto 4)="00" AND decodeOPC='1')) THEN
						CASE opcode(8 downto 6) IS		-- Destination mode
							WHEN "000"|"001" =>						-- Dn, An
									set_exec(Regwrena) <= '1';
							WHEN "010"|"011"|"100" =>				-- (An), (An)+, -(An)
								IF opcode(6)='1' THEN	-- (An)+
									set(postadd) <= '1';
									IF opcode(11 downto 9)="111" THEN
										set(use_SP) <= '1';
									END IF;
								END IF;
								IF opcode(8)='1' THEN	-- -(An)
									set(presub) <= '1';
									IF opcode(11 downto 9)="111" THEN
										set(use_SP) <= '1';
									END IF;
								END IF;
								setstate <= "11";
								next_micro_state <= nop;
								IF nextpass='0' THEN
									set(write_reg) <= '1';
								END IF;
							WHEN "101" =>				-- (d16,An)
								next_micro_state <= st_dAn1;
							WHEN "110" =>				-- (d8,An,Xn)
								next_micro_state <= st_AnXn1;
								getbrief <= '1';
							WHEN "111" =>
								CASE opcode(11 downto 9) IS
									WHEN "000" =>				-- (xxxx).W
										next_micro_state <= st_nn;
									WHEN "001" =>				-- (xxxx).L
										set(longaktion) <= '1';
										next_micro_state <= st_nn;
									WHEN OTHERS => NULL;
								END CASE;
							WHEN OTHERS => NULL;
						END CASE;
					END IF;
				ELSE
					trap_illegal <= '1';
					trapmake <= '1';
				END IF;
				
---- 0100 - Miscellaneous operations ---------------------------------------		
			WHEN "0100" =>				
				IF opcode(8)='1' THEN		-- LEA, EXTB.L, CHK
					IF opcode(6)='1' THEN		-- LEA, EXTB.L
						IF opcode(11 downto 9)="100" AND opcode(5 downto 3)="000" THEN -- EXTB.L (68020+)
							IF opcode(7)='1' AND cpu(1)='1' THEN
								source_lowbits <= '1';
								set_exec(opcEXT) <= '1';
								set_exec(opcEXTB) <= '1';
								set_exec(opcMOVE) <= '1';
								set_exec(Regwrena) <= '1';
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						ELSE								-- LEA
							IF opcode(7)='1' AND
							   (opcode(5)='1' OR opcode(4 downto 3)="10") AND
							   opcode(5 downto 3)/="100" AND opcode(5 downto 2)/="1111" THEN -- EA restrictions
								source_lowbits <= '1';
								source_areg <= '1';
								ea_only <= '1';				-- Calculate EA only
								set_exec(Regwrena) <= '1';
								set_exec(opcMOVE) <='1';
								set(no_Flags) <='1';
								IF opcode(5 downto 3)="010" THEN  	-- LEA (An),An
									dest_areg <= '1';
									dest_hbits <= '1';
								ELSE
									ea_build_now <= '1';
								END IF;	
								IF set(get_ea_now)='1' THEN
									setstate <= "01";
									set_direct_data <= '1';
								END IF;
								IF setexecOPC='1' THEN
									dest_areg <= '1';
									dest_hbits <= '1';
								END IF;
							ELSE
								trap_illegal <='1';
								trapmake <='1';
							END IF;
						END IF;
					ELSE								-- CHK
						IF opcode(5 downto 3)/="001" AND -- An not allowed
						   (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00") THEN -- EA restrictions
							IF opcode(7)='1' THEN		-- CHK.W
								datatype <= "01";	
								set(trap_chk) <= '1';
								IF (c_out(1)='0' OR OP1out(15)='1' OR OP2out(15)='1') AND exec(opcCHK)='1' THEN
									trapmake <= '1';
								END IF;
							ELSIF cpu(1)='1' THEN   	-- CHK.L (68020+)
								datatype <= "10";	
								set(trap_chk) <= '1';
								IF (c_out(2)='0' OR OP1out(31)='1' OR OP2out(31)='1') AND exec(opcCHK)='1' THEN
									trapmake <= '1';
								END IF;
							ELSE
								trap_illegal <= '1';		
								trapmake <= '1';
							END IF;
							IF opcode(7)='1' OR cpu(1)='1' THEN
								IF (nextpass='1' OR opcode(5 downto 4)="00") AND exec(opcCHK)='0' AND micro_state=idle THEN
									set_exec(opcCHK) <= '1';
								END IF;
								ea_build_now <= '1';
								set(addsub) <= '1';
								IF setexecOPC='1' THEN
									dest_hbits <= '1';
									source_lowbits <='1';
								END IF;
							END IF;
						ELSE
							trap_illegal <= '1';
							trapmake <= '1';
						END IF;
					END IF;
				ELSE
					CASE opcode(11 downto 9) IS
						WHEN "000"=>						-- NEGX, CLR, MOVE from SR/CCR
							IF (opcode(5 downto 3)/="001" AND -- An not allowed
							   (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00")) THEN -- EA restrictions
								IF opcode(7 downto 6)="11" THEN					-- MOVE from SR
									IF SR_Read=0 OR (cpu(0)='0' AND SR_Read=2) OR SVmode='1'  THEN
										ea_build_now <= '1';
										set_exec(opcMOVESR) <= '1';
										datatype <= "01";
										write_back <='1';							
										IF cpu(0)='1' AND state="10" AND addrvalue='0' THEN
											skipFetch <= '1';		-- 68010+ doesn't read before write
										END IF;
										IF opcode(5 downto 4)="00" THEN
											set_exec(Regwrena) <= '1';
										END IF;
									ELSE
										trap_priv <= '1';
										trapmake <= '1';
									END IF;
								ELSE									-- NEGX
									ea_build_now <= '1';
									set_exec(use_XZFlag) <= '1';	-- Use X flag
									write_back <='1';
									set_exec(opcADD) <= '1';
									set(addsub) <= '1';				-- Subtract
									source_lowbits <= '1';
									IF opcode(5 downto 4)="00" THEN
										set_exec(Regwrena) <= '1';
									END IF;
									IF setexecOPC='1' THEN
										set(OP1out_zero) <= '1';	-- 0 - source
									END IF;
								END IF;
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						WHEN "001"=>						-- CLR, MOVE from CCR
							IF (opcode(5 downto 3)/="001" AND -- An not allowed
							   (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00")) THEN -- EA restrictions
								IF opcode(7 downto 6)="11" THEN					-- MOVE from CCR (68010+)
									IF SR_Read=1 OR (cpu(0)='1' AND SR_Read=2) THEN
										ea_build_now <= '1';
										set_exec(opcMOVESR) <= '1';
										datatype <= "01";
										write_back <='1';							
										IF opcode(5 downto 4)="00" THEN
											set_exec(Regwrena) <= '1';
										END IF;
									ELSE
										trap_illegal <= '1';
										trapmake <= '1';
									END IF;
								ELSE											-- CLR
									ea_build_now <= '1';
									write_back <='1';
									set_exec(opcAND) <= '1';
									IF cpu(0)='1' AND state="10" AND addrvalue='0' THEN
										skipFetch <= '1';		-- 68010+ doesn't read before write
									END IF;
									IF setexecOPC='1' THEN
										set(OP1out_zero) <= '1';	-- Clear to zero
									END IF;
									IF opcode(5 downto 4)="00" THEN
										set_exec(Regwrena) <= '1';
									END IF;
								END IF;
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						WHEN "010"=>						-- NEG, MOVE to CCR
							IF opcode(7 downto 6)="11" THEN					-- MOVE to CCR
								IF opcode(5 downto 3)/="001" AND -- An not allowed
								   (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00") THEN -- EA restrictions
									ea_build_now <= '1';
									datatype <= "01";
									source_lowbits <= '1';
									IF (decodeOPC='1' AND opcode(5 downto 4)="00") OR (state="10" AND addrvalue='0') OR direct_data='1' THEN
										set(to_CCR) <= '1';
									END IF;
								ELSE
									trap_illegal <= '1';
									trapmake <= '1';
								END IF;
							ELSE											-- NEG
								IF (opcode(5 downto 3)/="001" AND -- An not allowed
								   (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00")) THEN -- EA restrictions
									ea_build_now <= '1';
									write_back <='1';
									set_exec(opcADD) <= '1';
									set(addsub) <= '1';
									source_lowbits <= '1';
									IF opcode(5 downto 4)="00" THEN
										set_exec(Regwrena) <= '1';
									END IF;
									IF setexecOPC='1' THEN
										set(OP1out_zero) <= '1';	-- 0 - source
									END IF;
								ELSE
									trap_illegal <= '1';
									trapmake <= '1';
								END IF;
							END IF;
						WHEN "011"=>										-- NOT, MOVE to SR
							IF opcode(7 downto 6)="11" THEN					-- MOVE to SR
								IF opcode(5 downto 3)/="001" AND -- An not allowed
								   (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00") THEN -- EA restrictions
									IF SVmode='1' THEN
										ea_build_now <= '1';
										datatype <= "01";
										source_lowbits <= '1';
										IF (decodeOPC='1' AND opcode(5 downto 4)="00") OR (state="10" AND addrvalue='0') OR direct_data='1' THEN
											set(to_SR) <= '1';
											set(to_CCR) <= '1';
										END IF;
										IF exec(to_SR)='1' OR (decodeOPC='1' AND opcode(5 downto 4)="00") OR (state="10" AND addrvalue='0') OR direct_data='1' THEN
											setstate <="01";
										END IF;
									ELSE
										trap_priv <= '1';
										trapmake <= '1';
									END IF;
								ELSE
									trap_illegal <= '1';
									trapmake <= '1';
								END IF;
							ELSE											-- NOT
								IF opcode(5 downto 3)/="001" AND -- An not allowed
								   (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00") THEN -- EA restrictions
									ea_build_now <= '1';
									write_back <='1';
									set_exec(opcEOR) <= '1';
									set_exec(ea_data_OP1) <= '1';
									IF opcode(5 downto 3)="000" THEN
										set_exec(Regwrena) <= '1';
									END IF;
									IF setexecOPC='1' THEN
										set(OP2out_one) <= '1';		-- XOR with all 1s
									END IF;
								ELSE
									trap_illegal <= '1';
									trapmake <= '1';
								END IF;
							END IF;
						WHEN "100"|"110"=>					-- MOVEM, EXT, SWAP, PEA, MUL/DIV.L
							IF opcode(7)='1' THEN			-- MOVEM, EXT
								IF opcode(5 downto 3)="000" AND opcode(10)='0' THEN		-- EXT
									source_lowbits <= '1';
									set_exec(opcEXT) <= '1';
									set_exec(opcMOVE) <= '1';
									set_exec(Regwrena) <= '1';	
									IF opcode(6)='0' THEN
										datatype <= "01";		-- EXT.W
										set_exec(opcEXTB) <= '1';
									END IF;
								ELSE													-- MOVEM
									IF (opcode(10)='1' OR ((opcode(5)='1' OR opcode(4 downto 3)="10") AND
									   (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00"))) AND
									   (opcode(10)='0' OR (opcode(5 downto 4)/="00" AND
									   opcode(5 downto 3)/="100" AND
									   opcode(5 downto 2)/="1111")) THEN -- EA restrictions
										ea_only <= '1';
										set(no_Flags) <= '1';
										IF opcode(6)='0' THEN
											datatype <= "01";		-- Word transfer
										END IF;
										IF (opcode(5 downto 3)="100" OR opcode(5 downto 3)="011") AND state="01" THEN	-- -(An), (An)+
											set_exec(save_memaddr) <= '1';
											set_exec(Regwrena) <= '1';
										END IF;
										IF opcode(5 downto 3)="100" THEN	-- -(An)
											movem_presub <= '1';
											set(subidx) <= '1';
										END IF;
										IF state="10" AND addrvalue='0' THEN
											set(Regwrena) <= '1';
											set(opcMOVE) <= '1';
										END IF;
										IF decodeOPC='1' THEN
											set(get_2ndOPC) <='1';
											IF opcode(5 downto 3)="010" OR opcode(5 downto 3)="011" OR opcode(5 downto 3)="100" THEN
												next_micro_state <= movem1;
											ELSE
												next_micro_state <= nop;
												set(ea_build) <= '1';
											END IF;
										END IF;
										IF set(get_ea_now)='1' THEN
											IF movem_run='1' THEN
												set(movem_action) <= '1';
												IF opcode(10)='0' THEN
													setstate <="11";
													set(write_reg) <= '1';
												ELSE
													setstate <="10";
												END IF;
												next_micro_state <= movem2;
												set(mem_addsub) <= '1';
											ELSE
												setstate <="01";
											END IF;
										END IF;
									ELSE
										trap_illegal <= '1';
										trapmake <= '1';
									END IF;
								END IF;	
							ELSE
								IF opcode(10)='1' THEN						-- MUL.L, DIV.L (68020+)
	 								-- FPGA Hardware Multiplier for long operations
									IF opcode(8 downto 7)="00" AND opcode(5 downto 3)/="001" AND (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00") AND -- EA restrictions
									   MUL_Hardware=1 AND (opcode(6)='0' AND (MUL_Mode=1 OR (cpu(1)='1' AND MUL_Mode=2))) THEN
										IF decodeOPC='1' THEN
											next_micro_state <= nop;
											set(get_2ndOPC) <= '1';
											set(ea_build) <= '1';
										END IF;
										IF (micro_state=idle AND nextpass='1') OR (opcode(5 downto 4)="00" AND exec(ea_build)='1') THEN
											dest_2ndHbits <= '1';
											datatype <= "10";
											set(opcMULU) <= '1';
											set(write_lowlong) <= '1';
											IF sndOPC(10)='1' THEN
												setstate <="01";
												next_micro_state <= mul_end2;
											END IF;
											set(Regwrena) <= '1';
										END IF;
										source_lowbits <='1';
										datatype <= "10";

	 								-- Software Multiplier/Divider implementation
									ELSIF opcode(8 downto 7)="00" AND opcode(5 downto 3)/="001" AND (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00") AND -- EA restrictions
									   ((opcode(6)='1' AND (DIV_Mode=1 OR (cpu(1)='1' AND DIV_Mode=2))) OR
									   (opcode(6)='0' AND (MUL_Mode=1 OR (cpu(1)='1' AND MUL_Mode=2)))) THEN
										IF decodeOPC='1' THEN
											next_micro_state <= nop;
											set(get_2ndOPC) <= '1';
											set(ea_build) <= '1';
										END IF;
										IF (micro_state=idle AND nextpass='1') OR (opcode(5 downto 4)="00" AND exec(ea_build)='1')THEN
											setstate <="01";
											dest_2ndHbits <= '1';
											source_2ndLbits <= '1';
											IF opcode(6)='1' THEN
												next_micro_state <= div1;	-- Division
											ELSE	
												next_micro_state <= mul1;	-- Multiplication
												set(ld_rot_cnt) <= '1';
											END IF;
										END IF;
										source_lowbits <='1';
										IF nextpass='1' OR (opcode(5 downto 4)="00" AND decodeOPC='1') THEN	
											dest_hbits <= '1';
										END IF;
										datatype <= "10";
									ELSE
										trap_illegal <= '1';
										trapmake <= '1';
									END IF;
					
								ELSE							-- PEA, SWAP, NBCD, LINK.L
									IF opcode(6)='1' THEN
										datatype <= "10";
										IF opcode(5 downto 3)="000" THEN 		-- SWAP
											set_exec(opcSWAP) <= '1';
											set_exec(Regwrena) <= '1';	
										ELSIF opcode(5 downto 3)="001" THEN 	-- BKPT (not implemented)
											trap_illegal <= '1';
											trapmake <= '1';
										ELSE									-- PEA
											IF (opcode(5)='1' OR opcode(4 downto 3)="10") AND
											   opcode(5 downto 3)/="100" AND
											   opcode(5 downto 2)/="1111" THEN -- EA restrictions
												ea_only <= '1';
												ea_build_now <= '1';
												IF nextpass='1' AND micro_state=idle THEN
													set(presub) <= '1';
													setstackaddr <='1';
													setstate <="11";
													next_micro_state <= nop;
												END IF;
												IF set(get_ea_now)='1' THEN
													setstate <="01";
												END IF;
											ELSE
												trap_illegal <= '1';
												trapmake <= '1';
											END IF;
										END IF;
									ELSE
										IF opcode(5 downto 3)="001" THEN -- LINK.L (68020+)
											datatype <= "10";
											set_exec(opcADD) <= '1';				-- For displacement
											set_exec(Regwrena) <= '1';
											set(no_Flags) <= '1';
											IF decodeOPC='1' THEN
												set(linksp) <= '1';
												set(longaktion) <= '1';
												next_micro_state <= link1;
												set(presub) <= '1';
												setstackaddr <='1';
												set(mem_addsub) <= '1';
												source_lowbits <= '1';
												source_areg <= '1';
												set(store_ea_data) <= '1';
											END IF;
										ELSE						-- NBCD
											IF opcode(5 downto 3)/="001" AND -- An not allowed
											   (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00") THEN -- EA restrictions
												ea_build_now <= '1';
												set_exec(use_XZFlag) <= '1';
												write_back <='1';
												set_exec(opcADD) <= '1';
												set_exec(opcSBCD) <= '1';
												set(addsub) <= '1';
												source_lowbits <= '1';
												IF opcode(5 downto 4)="00" THEN
													set_exec(Regwrena) <= '1';
												END IF;
												IF setexecOPC='1' THEN
													set(OP1out_zero) <= '1';	-- 0 - source
												END IF;
											ELSE
												trap_illegal <= '1';
												trapmake <= '1';
											END IF;
										END IF;	
									END IF;
								END IF;
							END IF;
-- 0x4AXX							
						WHEN "101"=>						-- TST, TAS, ILLEGAL  
							IF opcode(7 downto 3)="11111" AND opcode(2 downto 1)/="00" THEN   -- 0x4AFC illegal, 0x4AFB BKP Sinclair QL
								trap_illegal <= '1';
								trapmake <= '1';
							ELSE
								IF (opcode(7 downto 6)/="11" OR -- TST
								   (opcode(5 downto 3)/="001" AND -- An not allowed for TAS
								   (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00"))) AND -- EA restrictions
								   ((opcode(7 downto 6)/="00" OR (opcode(5 downto 3)/="001")) AND
								   (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00")) THEN
									ea_build_now <= '1';
									IF setexecOPC='1' THEN
										source_lowbits <= '1';
										IF opcode(3)='1' THEN			-- TST.An (68020+)
											source_areg <= '1';
										END IF;
									END IF;
									set_exec(opcMOVE) <= '1';		-- Just test flags
									IF opcode(7 downto 6)="11" THEN		-- TAS
										set_exec_tas <= '1';
										write_back <= '1';
										datatype <= "00";				-- Byte operation
										IF opcode(5 downto 4)="00" THEN
											set_exec(Regwrena) <= '1';
										END IF;
									END IF;
								ELSE
									trap_illegal <= '1';
									trapmake <= '1';
								END IF;
							END IF;
						WHEN "111"=>					-- 4EXX - Misc. operations
							IF opcode(7)='1' THEN		-- JSR, JMP
								IF (opcode(5)='1' OR opcode(4 downto 3)="10") AND
								   opcode(5 downto 3)/="100" AND opcode(5 downto 2)/="1111" THEN -- EA restrictions
									datatype <= "10";
									ea_only <= '1';
									ea_build_now <= '1';
									IF exec(ea_to_pc)='1' THEN
										next_micro_state <= nop;
									END IF;
									IF nextpass='1' AND micro_state=idle AND opcode(6)='0' THEN	-- JSR
										set(presub) <= '1';
										setstackaddr <='1';
										setstate <="11";
										next_micro_state <= nopnop;
									END IF;
								
									-- Optimization for JMP/JSR n(Ax,Dn)
									IF micro_state=ld_AnXn1 AND brief(8)='0'THEN			
										skipFetch <= '1';
									END IF;
									IF state="00" THEN
										writePC <= '1';
									END IF;
									set(hold_dwr) <= '1';
									IF set(get_ea_now)='1' THEN					-- JSR completion
										IF exec(longaktion)='0' OR long_done='1' THEN
											skipFetch <= '1';
										END IF;
										setstate <="01";
										set(ea_to_pc) <= '1';
									END IF;
								ELSE
									trap_illegal <= '1';
									trapmake <= '1';
								END IF;
							ELSE						-- Various 4EXX instructions
								CASE opcode(6 downto 0) IS
									WHEN "1000000"|"1000001"|"1000010"|"1000011"|"1000100"|"1000101"|"1000110"|"1000111"|		-- TRAP #0-7
									     "1001000"|"1001001"|"1001010"|"1001011"|"1001100"|"1001101"|"1001110"|"1001111" =>	-- TRAP #8-15
											trap_trap <='1';
											trapmake <= '1';
									
									WHEN "1010000"|"1010001"|"1010010"|"1010011"|"1010100"|"1010101"|"1010110"|"1010111"=> 	-- LINK.W
										datatype <= "10";
										set_exec(opcADD) <= '1';				-- For displacement
										set_exec(Regwrena) <= '1';
										set(no_Flags) <= '1';
										IF decodeOPC='1' THEN
											next_micro_state <= link1;
											set(presub) <= '1';
											setstackaddr <='1';
											set(mem_addsub) <= '1';
											source_lowbits <= '1';
											source_areg <= '1';
											set(store_ea_data) <= '1';
										END IF;
									
									WHEN "1011000"|"1011001"|"1011010"|"1011011"|"1011100"|"1011101"|"1011110"|"1011111" =>	-- UNLK
										datatype <= "10";
										set_exec(Regwrena) <= '1';
										set_exec(opcMOVE) <= '1';						
										set(no_Flags) <= '1';
										IF decodeOPC='1' THEN
											setstate <= "01";
											next_micro_state <= unlink1;
											set(opcMOVE) <= '1';
											set(Regwrena) <= '1';
											setstackaddr <='1';
											source_lowbits <= '1';
											source_areg <= '1';
										END IF;
									
									WHEN "1100000"|"1100001"|"1100010"|"1100011"|"1100100"|"1100101"|"1100110"|"1100111" =>	-- MOVE An,USP
										IF SVmode='1' THEN
											set(to_USP) <= '1';
											source_lowbits <= '1';
											source_areg <= '1';
											datatype <= "10";
										ELSE
											trap_priv <= '1';
											trapmake <= '1';
										END IF;
									
									WHEN "1101000"|"1101001"|"1101010"|"1101011"|"1101100"|"1101101"|"1101110"|"1101111" =>	-- MOVE USP,An
										IF SVmode='1' THEN
											set(from_USP) <= '1';
											datatype <= "10";
											set_exec(Regwrena) <= '1';
										ELSE
											trap_priv <= '1';
											trapmake <= '1';
										END IF;
									
									WHEN "1110000" =>					-- RESET
										IF SVmode='0' THEN
											trap_priv <= '1';
											trapmake <= '1';
										ELSE
											set(opcRESET) <= '1';
											IF decodeOPC='1' THEN
												set(ld_rot_cnt) <= '1'; 
												set_rot_cnt <= "000000";	-- 124 cycles
											END IF;
										END IF;
										
									WHEN "1110001" =>					-- NOP
									
									WHEN "1110010" =>					-- STOP
										IF SVmode='0' THEN
											trap_priv <= '1';
											trapmake <= '1';
										ELSE
											IF decodeOPC='1' THEN
												setnextpass <= '1';
												set_stop <= '1';	
											END IF;
											IF stop='1' THEN
												skipFetch <= '1';
											END IF;		
										END IF;
									
									WHEN "1110011"|"1110111" =>  			-- RTE/RTR
										IF SVmode='1' OR opcode(2)='1' THEN
											IF decodeOPC='1' THEN
												setstate <= "10";
												set(postadd) <= '1';
												setstackaddr <= '1';
												IF opcode(2)='1' THEN
													set(directCCR) <= '1';	-- RTR
												ELSE	
													set(directSR) <= '1';	-- RTE
												END IF;
												next_micro_state <= rte1;
											END IF;
										ELSE
											trap_priv <= '1';
											trapmake <= '1';
										END IF;
										
									WHEN "1110100" =>  					-- RTD (68010+)
										datatype <= "10";
										IF decodeOPC='1' THEN
											setstate <= "10";
											set(postadd) <= '1';
											setstackaddr <= '1';
											set(direct_delta) <= '1';
											set(directPC) <= '1';
											set_direct_data <= '1';
											next_micro_state <= rtd1;
										END IF;
										
									WHEN "1110101" =>  					-- RTS
										datatype <= "10";
										IF decodeOPC='1' THEN
											setstate <= "10";
											set(postadd) <= '1';
											setstackaddr <= '1';
											set(direct_delta) <= '1';	
											set(directPC) <= '1';
											next_micro_state <= nopnop;
										END IF;
										
									WHEN "1110110" =>  					-- TRAPV
										IF decodeOPC='1' THEN
											setstate <= "01";
										END IF;	
										IF Flags(1)='1' AND state="01" THEN	-- V flag set
											trap_trapv <= '1';
											trapmake <= '1';
										END IF;
										
									WHEN "1111010"|"1111011" =>  			-- MOVEC (68010+)
										IF cpu="00" THEN
											trap_illegal <= '1';
											trapmake <= '1';
										ELSIF SVmode='0' THEN
											trap_priv <= '1';
											trapmake <= '1';
										ELSE
											datatype <= "10";	
											IF last_data_read(11 downto 0)=X"800" THEN
												set(from_USP) <= '1';
												IF opcode(0)='1' THEN
													set(to_USP) <= '1';
												END IF;
											END IF;
											IF opcode(0)='0' THEN
												set_exec(movec_rd) <= '1';	-- Read control register
											ELSE		
												set_exec(movec_wr) <= '1';	-- Write control register
											END IF;
											IF decodeOPC='1' THEN
												next_micro_state <= movec1;
												getbrief <='1';
											END IF;
										END IF;
									
									WHEN OTHERS =>	
										trap_illegal <= '1';
										trapmake <= '1';
								END CASE;	
							END IF;
						WHEN OTHERS => NULL;
					END CASE;
				END IF;	
					
---- 0101 - ADDQ/SUBQ/Scc/DBcc ---------------------------------------------
			WHEN "0101" => 								
					IF opcode(7 downto 6)="11" THEN -- DBcc/TRAPcc/Scc
						IF opcode(5 downto 3)="001" THEN -- DBcc
							IF decodeOPC='1' THEN
								next_micro_state <= dbcc1;
								set(OP2out_one) <= '1';		-- Decrement by 1
								data_is_source <= '1';
							END IF;
						ELSIF opcode(5 downto 3)="111" AND (opcode(2 downto 1)="01" OR opcode(2 downto 0)="100") THEN	-- TRAPcc (68020+)
							IF cpu(1)='1' THEN							
								IF opcode(2 downto 1)="01" THEN
									IF decodeOPC='1' THEN
										IF opcode(0)='1' THEN			-- Long displacement
											set(longaktion) <= '1';
										END IF;
										next_micro_state <= nop;
									END IF;
								ELSE
									IF decodeOPC='1' THEN
										setstate <= "01";
									END IF;
								END IF;
								IF exe_condition='1' AND decodeOPC='0' THEN
									trap_trapv <= '1';				-- Use TRAPV vector
									trapmake <= '1';
								END IF;
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						ELSIF (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00") THEN -- Scc
							datatype <= "00";			-- Byte operation
							ea_build_now <= '1';
							write_back <= '1';
							set_exec(opcScc) <= '1';
							IF cpu(0)='1' AND state="10" AND addrvalue='0' THEN
								skipFetch <= '1';		-- 68010+ optimization
							END IF;
							IF opcode(5 downto 4)="00" THEN
								set_exec(Regwrena) <= '1';
							END IF;
						ELSE
							trap_illegal <= '1';
							trapmake <= '1';
						END IF;
					ELSE					-- ADDQ, SUBQ
						IF opcode(7 downto 3)/="00001" AND
						   (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00") THEN -- EA restrictions
							ea_build_now <= '1';
							IF opcode(5 downto 3)="001" THEN	-- Address register - no flags
								set(no_Flags) <= '1';
							END IF;
							IF opcode(8)='1' THEN
								set(addsub) <= '1';				-- SUBQ
							END IF;
							write_back <= '1';
							set_exec(opcADDQ) <= '1';
							set_exec(opcADD) <= '1';
							set_exec(ea_data_OP1) <= '1';
							IF opcode(5 downto 4)="00" THEN
								set_exec(Regwrena) <= '1';
							END IF;
						ELSE
							trap_illegal <= '1';
							trapmake <= '1';
						END IF;
					END IF;
				
---- 0110 - Bcc/BSR --------------------------------------------------------		
			WHEN "0110" =>				-- Branch conditionally, BSR
				datatype <= "10";
				
				IF micro_state=idle THEN
					IF opcode(11 downto 8)="0001" THEN		-- BSR
						set(presub) <= '1';
						setstackaddr <='1';
						IF opcode(7 downto 0)="11111111" THEN
							next_micro_state <= bsr2;
							set(longaktion) <= '1';			-- 32-bit displacement
						ELSIF opcode(7 downto 0)="00000000" THEN
							next_micro_state <= bsr2;		-- 16-bit displacement
						ELSE	
							next_micro_state <= bsr1;		-- 8-bit displacement
							setstate <= "11";
							writePC <= '1';
						END IF;
					ELSE									-- Bcc
						IF opcode(7 downto 0)="11111111" THEN
							next_micro_state <= bra1;
							set(longaktion) <= '1';			-- 32-bit displacement
						ELSIF opcode(7 downto 0)="00000000" THEN
							next_micro_state <= bra1;		-- 16-bit displacement
						ELSE
							setstate <= "01";
							next_micro_state <= bra1;		-- 8-bit displacement
						END IF;
					END IF;
				END IF;	
				
-- 0111 - MOVEQ ------------------------------------------------------------		
			WHEN "0111" =>				-- MOVEQ - Quick move immediate to data register
				IF opcode(8)='0' THEN
					datatype <= "10";		-- Long operation
					set_exec(Regwrena) <= '1';
					set_exec(opcMOVEQ) <= '1';
					set_exec(opcMOVE) <= '1';
					dest_hbits <= '1';
				ELSE
					trap_illegal <= '1';
					trapmake <= '1';
				END IF;
				
---- 1000 - OR, DIVU, DIVS, SBCD ------------------------------------------		
			WHEN "1000" => 								
				IF opcode(7 downto 6)="11" THEN	-- DIVU, DIVS
					IF DIV_Mode/=3 AND
					   opcode(5 downto 3)/="001" AND (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00") THEN -- EA restrictions
						IF opcode(5 downto 4)="00" THEN	-- Register direct
							regdirectsource <= '1';
						END IF;
						IF (micro_state=idle AND nextpass='1') OR (opcode(5 downto 4)="00" AND decodeOPC='1') THEN
							setstate <="01";
							next_micro_state <= div1;
						END IF;
						ea_build_now <= '1';
						IF z_error='0' AND set_V_Flag='0' THEN
							set_exec(Regwrena) <= '1';
						END IF;
						source_lowbits <='1';
						IF nextpass='1' OR (opcode(5 downto 4)="00" AND decodeOPC='1') THEN
							dest_hbits <= '1';
						END IF;
						datatype <= "01";		-- Word operation
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				ELSIF opcode(8)='1' AND opcode(5 downto 4)="00" THEN	-- SBCD, PACK, UNPACK
					IF opcode(7 downto 6)="00" THEN	-- SBCD
						build_bcd <= '1';
						set_exec(opcADD) <= '1';
						set_exec(opcSBCD) <= '1';
						set(addsub) <= '1';
					ELSIF opcode(7 downto 6)="01" OR opcode(7 downto 6)="10" THEN	-- PACK, UNPACK (68020+)
						set_exec(ea_data_OP1) <= '1';
						set(no_Flags) <= '1';
						source_lowbits <='1';
						IF opcode(7 downto 6) = "01" THEN	-- PACK
							set_exec(opcPACK) <= '1';
							datatype <= "01";				-- Word source
						ELSE								-- UNPACK
							set_exec(opcUNPACK) <= '1';
							datatype <= "00";				-- Byte source
						END IF;
						IF opcode(3)='0' THEN				-- Register to register
							IF opcode(7 downto 6) = "01" THEN	-- PACK
								set_datatype <= "00";		-- Byte destination
							ELSE								-- UNPACK
								set_datatype <= "01";		-- Word destination
							END IF;
							set_exec(Regwrena) <= '1';
							dest_hbits <= '1';
							IF decodeOPC='1' THEN
								next_micro_state <= nop;
								set(store_ea_packdata) <= '1';
								set(store_ea_data) <= '1';
							END IF;
						ELSE				-- Memory to memory: -(Ax),-(Ay)
							write_back <= '1';
							IF decodeOPC='1' THEN
								next_micro_state <= pack1;
								set_direct_data <= '1';
							END IF;
						END IF;
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				ELSE									-- OR
					IF opcode(7 downto 6)/="11" AND -- Valid operation mode
					   ((opcode(8)='0' AND opcode(5 downto 3)/="001" AND (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00")) OR -- Source EA restrictions
					   (opcode(8)='1' AND opcode(5 downto 4)/="00" AND (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00"))) THEN -- Dest EA restrictions
						set_exec(opcOR) <= '1';
						build_logical <= '1';
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				END IF;
				
---- 1001, 1101 - SUB, ADD ------------------------------------------------		
			WHEN "1001"|"1101" => 						
				IF opcode(8 downto 3)/="000001" AND -- Byte size with address register not allowed
				   (((opcode(8)='0' OR opcode(7 downto 6)="11") AND (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00")) OR -- Source EA restrictions
				   (opcode(8)='1' AND (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00"))) THEN -- Dest EA restrictions
					set_exec(opcADD) <= '1';
					ea_build_now <= '1';
					IF opcode(14)='0' THEN		-- SUB
						set(addsub) <= '1';
					END IF;
					IF opcode(7 downto 6)="11" THEN	-- ADDA, SUBA
						IF opcode(8)='0' THEN	-- .W
							datatype <= "01";	
						END IF;
						set_exec(Regwrena) <= '1';
						source_lowbits <='1';
						IF opcode(3)='1' THEN
							source_areg <= '1';
						END IF;
						set(no_Flags) <= '1';		-- Address operations don't affect flags
						IF setexecOPC='1' THEN
							dest_areg <='1';
							dest_hbits <= '1';
						END IF;
					ELSE
						IF opcode(8)='1' AND opcode(5 downto 4)="00" THEN		-- ADDX, SUBX
							build_bcd <= '1';
						ELSE							-- Normal SUB, ADD
							build_logical <= '1';
						END IF;
					END IF;
				ELSE
						trap_illegal <= '1';
						trapmake <= '1';
				END IF;
				
---- 1010 - Line A trap ---------------------------------------------------		
			WHEN "1010" => 							
				trap_1010 <= '1';
				trapmake <= '1';
				
---- 1011 - CMP, EOR ------------------------------------------------------		
			WHEN "1011" => 							
				IF opcode(7 downto 6)="11" THEN	-- CMPA
					IF opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00" THEN -- Source EA restrictions
						ea_build_now <= '1';
						IF opcode(8)='0' THEN	-- CMPA.W
							datatype <= "01";	
							set_exec(opcCPMAW) <= '1';
						END IF;
						set_exec(opcCMP) <= '1';
						IF setexecOPC='1' THEN
							source_lowbits <='1';
							IF opcode(3)='1' THEN
								source_areg <= '1';
							END IF;
							dest_areg <='1';
							dest_hbits <= '1';
						END IF;
						set(addsub) <= '1';
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				ELSE	-- CMPM, EOR, CMP
					IF opcode(8)='1' THEN
						IF opcode(5 downto 3)="001" THEN		-- CMPM (Ay)+,(Ax)+
							ea_build_now <= '1';
							set_exec(opcCMP) <= '1';
							IF decodeOPC='1' THEN
								IF opcode(2 downto 0)="111" THEN
									set(use_SP) <= '1';
								END IF;
								setstate <= "10";
								set(update_ld) <= '1';
								set(postadd) <= '1';
								next_micro_state <= cmpm;
							END IF;
							set_exec(ea_data_OP1) <= '1';
							set(addsub) <= '1';
						ELSE						-- EOR
							IF opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00" THEN -- Dest EA restrictions
								ea_build_now <= '1';
								build_logical <= '1';
								set_exec(opcEOR) <= '1';
							ELSE
								trap_illegal <= '1';
								trapmake <= '1';
							END IF;
						END IF;
					ELSE							-- CMP
						IF opcode(8 downto 3)/="000001" AND -- Byte with address register not allowed
						   (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00") THEN -- Source EA restrictions
							ea_build_now <= '1';
							build_logical <= '1';
							set_exec(opcCMP) <= '1';
							set(addsub) <= '1';
						ELSE
							trap_illegal <= '1';
							trapmake <= '1';
						END IF;
					END IF;
				END IF;
				
---- 1100 - AND, EXG, MUL -------------------------------------------------		
			WHEN "1100" => 								
				IF opcode(7 downto 6)="11" THEN	-- MULU, MULS
					IF MUL_Mode/=3 AND
					   opcode(5 downto 3)/="001" AND (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00") THEN -- EA restrictions
						IF opcode(5 downto 4)="00" THEN	-- Register direct
							regdirectsource <= '1';
						END IF;
						IF (micro_state=idle AND nextpass='1') OR (opcode(5 downto 4)="00" AND decodeOPC='1') THEN	
							IF MUL_Hardware=0 THEN		-- Software multiply
								setstate <="01";
								set(ld_rot_cnt) <= '1';
								next_micro_state <= mul1;
							ELSE						-- Hardware multiply
								set_exec(write_lowlong) <= '1';
								set_exec(opcMULU) <= '1';
							END IF;
						END IF;
						ea_build_now <= '1';
						set_exec(Regwrena) <= '1';
						source_lowbits <='1';
						IF (nextpass='1') OR (opcode(5 downto 4)="00" AND decodeOPC='1') THEN
							dest_hbits <= '1';
						END IF;
						datatype <= "01";		-- Word source
						IF setexecOPC='1' THEN
							datatype <= "10";	-- Long result
						END IF;
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				ELSIF opcode(8)='1' AND opcode(5 downto 4)="00" THEN	-- EXG, ABCD
					IF opcode(7 downto 6)="00" THEN	-- ABCD
						build_bcd <= '1';
						set_exec(opcADD) <= '1';
						set_exec(opcABCD) <= '1';
					ELSE									-- EXG
						IF opcode(7 downto 4)="0100" OR opcode(7 downto 3)="10001" THEN
							datatype <= "10";
							set(Regwrena) <= '1';
							set(exg) <= '1';
							set(alu_move) <= '1';
							IF opcode(6)='1' AND opcode(3)='1' THEN
								dest_areg <= '1';
								source_areg <= '1';
							END IF;
							IF decodeOPC='1' THEN
								setstate <= "01";
							ELSE
								dest_hbits <= '1';
							END IF;
						ELSE
							trap_illegal <= '1';
							trapmake <= '1';
						END IF;
					END IF;
				ELSE									-- AND
					IF opcode(7 downto 6)/="11" AND -- Valid operation mode
					   ((opcode(8)='0' AND opcode(5 downto 3)/="001" AND (opcode(5 downto 2)/="1111" OR opcode(1 downto 0)="00")) OR -- Source EA restrictions
					   (opcode(8)='1' AND opcode(5 downto 4)/="00" AND (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00"))) THEN -- Dest EA restrictions
						set_exec(opcAND) <= '1';
						build_logical <= '1';
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
				END IF;
				
---- 1110 - Shift/Rotate, Bit Field ---------------------------------------		
			WHEN "1110" => 								
				IF opcode(7 downto 6)="11" THEN
					IF opcode(11)='0' THEN			-- Memory shift/rotate
					   IF (opcode(5 downto 4)/="00" AND (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00")) THEN -- EA restrictions
							IF BarrelShifter=0 THEN
								set_exec(opcROT) <= '1';
							ELSE
								set_exec(exec_BS) <='1';	-- Barrel shifter
							END IF;
							ea_build_now <= '1';
							datatype <= "01";				-- Word operation
							set_rot_bits <= opcode(10 downto 9);
							set_exec(ea_data_OP1) <= '1';
							write_back <= '1';
						ELSE
							trap_illegal <= '1';
							trapmake <= '1';
						END IF;
					ELSE		-- Bit field operations (68020+)
						IF BitField=0 OR (cpu(1)='0' AND BitField=2) OR
						   ((opcode(10 downto 9)="11" OR opcode(10 downto 8)="010" OR opcode(10 downto 8)="100") AND
						   (opcode(5 downto 3)="001" OR opcode(5 downto 3)="011" OR opcode(5 downto 3)="100" OR (opcode(5 downto 3)="111" AND opcode(2 downto 1)/="00"))) OR
						   ((opcode(10 downto 9)="00" OR opcode(10 downto 8)="011" OR opcode(10 downto 8)="101") AND
						   (opcode(5 downto 3)="001" OR opcode(5 downto 3)="011" OR opcode(5 downto 3)="100" OR opcode(5 downto 2)="1111")) THEN
							trap_illegal <= '1';
							trapmake <= '1';
						ELSE
							IF decodeOPC='1' THEN
								next_micro_state <= nop;
								set(get_2ndOPC) <= '1';
								set(ea_build) <= '1';
							END IF;
							set_exec(opcBF) <= '1';
-- Bit field operations: 000-BFTST, 001-BFEXTU, 010-BFCHG, 011-BFEXTS, 100-BFCLR, 101-BFFFO, 110-BFSET, 111-BFINS
							IF opcode(10)='1' OR opcode(8)='0' THEN
								set_exec(opcBFwb) <= '1';	-- Write-back operations
							END IF;
							IF opcode(10 downto 8)="111" THEN	-- BFINS
								set_exec(ea_data_OP1) <= '1';
							END IF;
							IF opcode(10 downto 8)="010" OR opcode(10 downto 8)="100" OR opcode(10 downto 8)="110" OR opcode(10 downto 8)="111" THEN
								write_back <= '1';
							END IF;
							ea_only <= '1';
							IF opcode(10 downto 8)="001" OR opcode(10 downto 8)="011" OR opcode(10 downto 8)="101" THEN
								set_exec(Regwrena) <= '1';		-- BFEXTU, BFEXTS, BFFFO
							END IF;
							IF opcode(4 downto 3)="00" THEN	-- Register bit field
								IF opcode(10 downto 8)/="000" THEN
									set_exec(Regwrena) <= '1';
								END IF;
								IF exec(ea_build)='1' THEN
									dest_2ndHbits <= '1';
									source_2ndLbits <= '1';
									set(get_bfoffset) <='1';
									setstate <= "01";
								END IF;
							END IF;
							IF set(get_ea_now)='1' THEN
								setstate <= "01";
							END IF;
							IF exec(get_ea_now)='1' THEN
								dest_2ndHbits <= '1';
								source_2ndLbits <= '1';
								set(get_bfoffset) <='1';
								setstate <= "01";
								set(mem_addsub) <='1';
								next_micro_state <= bf1;
							END IF;
							IF setexecOPC='1' THEN
								IF opcode(10 downto 8)="111" THEN	-- BFINS source
									source_2ndHbits <= '1';
								ELSE
									source_lowbits <= '1';
								END IF;
								IF opcode(10 downto 8)="001" OR opcode(10 downto 8)="011" OR opcode(10 downto 8)="101" THEN	-- BFEXT, BFFFO destination
									dest_2ndHbits <= '1';
								END IF;
							END IF;
						END IF;
					END IF;
				ELSE								-- Register shift/rotate
					data_is_source <= '1';
					IF BarrelShifter=0 OR (cpu(1)='0' AND BarrelShifter=2) THEN
						set_exec(opcROT) <= '1';
						set_rot_bits <= opcode(4 downto 3);
						set_exec(Regwrena) <= '1';
						IF decodeOPC='1' THEN
							IF opcode(5)='1' THEN			-- Register count
								next_micro_state <= rota1;
								set(ld_rot_cnt) <= '1';
								setstate <= "01";
							ELSE							-- Immediate count
								set_rot_cnt(2 downto 0) <= opcode(11 downto 9);
								IF opcode(11 downto 9)="000" THEN
									set_rot_cnt(3) <='1';	-- Count of 0 means 8
								ELSE
									set_rot_cnt(3) <='0';
								END IF;
							END IF;
						END IF;
					ELSE									-- Barrel shifter
						set_exec(exec_BS) <='1';
						set_rot_bits <= opcode(4 downto 3);
						set_exec(Regwrena) <= '1';
					END IF;
				END IF;
				
---- 1111 - Coprocessor/Line F trap ---------------------------------------		
			WHEN "1111" =>
				IF cpu(1)='1' AND opcode(8 downto 6)="100" THEN -- cpSAVE (68020+)
					IF opcode(5 downto 4)/="00" AND opcode(5 downto 3)/="011" AND
					   (opcode(5 downto 3)/="111" OR opcode(2 downto 1)="00") THEN -- EA restrictions
						IF opcode(11 downto 9)/="000" THEN
							IF SVmode='1' THEN
								IF opcode(5)='0' AND opcode(5 downto 4)/="01" THEN
									-- cpSAVE not implemented
									trap_illegal <= '1';
									trapmake <= '1';
								ELSE
									trap_1111 <= '1';
									trapmake <= '1';
								END IF;
							ELSE
								trap_priv <= '1';
								trapmake <= '1';
							END IF;
						ELSE
							IF SVmode='1' THEN
								trap_1111 <= '1';
								trapmake <= '1';
							ELSE
								trap_priv <= '1';
								trapmake <= '1';
							END IF;
						END IF;
					ELSE
						trap_1111 <= '1';
						trapmake <= '1';
					END IF;
				ELSIF cpu(1)='1' AND opcode(8 downto 6)="101" THEN -- cpRESTORE (68020+)
					IF opcode(5 downto 4)/="00" AND opcode(5 downto 3)/="100" AND
					   (opcode(5 downto 3)/="111" OR (opcode(2 downto 1)/="11" AND
					   opcode(2 downto 0)/="101")) THEN -- EA restrictions
						IF opcode(5 downto 1)/="11110" THEN
							IF opcode(11 downto 9)="001" OR opcode(11 downto 9)="010" THEN
								IF SVmode='1' THEN
									IF opcode(5 downto 3)="101" THEN
										-- cpRESTORE not implemented
										trap_illegal <= '1';
										trapmake <= '1';
									ELSE
										trap_1111 <= '1';
										trapmake <= '1';
									END IF;
								ELSE
									trap_priv <= '1';
									trapmake <= '1';
								END IF;
							ELSE
								IF SVmode='1' THEN
									trap_1111 <= '1';
									trapmake <= '1';
								ELSE
									trap_priv <= '1';
									trapmake <= '1';
								END IF;
							END IF;
						ELSE
							trap_1111 <= '1';
							trapmake <= '1';
						END IF;
					ELSE
						trap_1111 <= '1';
						trapmake <= '1';
					END IF;
				ELSE
					trap_1111 <= '1';
					trapmake <= '1';
				END IF;
							
---- Default --------------------------------------------------------------		
			WHEN OTHERS =>
				trap_illegal <= '1';
				trapmake <= '1';

		END CASE;

-- Common code for logical operations (AND, OR, EOR, CMP)
		IF build_logical='1' THEN
			ea_build_now <= '1';
			IF set_exec(opcCMP)='0' AND (opcode(8)='0' OR opcode(5 downto 4)="00" ) THEN					
				set_exec(Regwrena) <= '1';
			END IF;
			IF opcode(8)='1' THEN		-- <ea> OP Dn -> <ea>
				write_back <= '1';
				set_exec(ea_data_OP1) <= '1';
			ELSE						-- Dn OP <ea> -> Dn
				source_lowbits <='1';
				IF opcode(3)='1' THEN		-- Address register source for CMP
					source_areg <= '1';
				END IF;
				IF setexecOPC='1' THEN
					dest_hbits <= '1';
				END IF;
			END IF;
		END IF;
		
-- Common code for BCD operations (ABCD, SBCD)
		IF build_bcd='1' THEN
			set_exec(use_XZFlag) <= '1';
			set_exec(ea_data_OP1) <= '1';
			write_back <= '1';
			source_lowbits <='1';
			IF opcode(3)='1' THEN		-- Memory to memory mode
				IF decodeOPC='1' THEN
					IF opcode(2 downto 0)="111" THEN
						set(use_SP) <= '1';
					END IF;
					setstate <= "10";
					set(update_ld) <= '1';
					set(presub) <= '1';
					next_micro_state <= op_AxAy;
					dest_areg <= '1';				
				END IF;
			ELSE						-- Register to register
				dest_hbits <= '1';
				set_exec(Regwrena) <= '1';
			END IF;
		END IF;
		

------------------------------------------------------------------------------		
-- Division by zero handling	
------------------------------------------------------------------------------		
		IF set_Z_error='1'  THEN		
			trapmake <= '1';			
			IF trapd='0' THEN
				writePC <= '1';
			END IF;			
		END IF;	
		
-----------------------------------------------------------------------------
-- Execute microcode sequences
-----------------------------------------------------------------------------
		IF rising_edge(clk) THEN
	        IF Reset='1' THEN
				micro_state <= ld_nn;
			ELSIF clkena_lw='1' THEN
				trapd <= trapmake;
				micro_state <= next_micro_state;
			END IF;
		END IF;

			CASE micro_state IS
			-- Effective address calculation microstates
				WHEN ld_nn =>		-- Load absolute address (nnnn).W/L
					set(get_ea_now) <='1';
					setnextpass <= '1';
					set(addrlong) <= '1';
					
				WHEN st_nn =>		-- Store to absolute address (nnnn).W/L
					setstate <= "11";
					set(addrlong) <= '1';
					next_micro_state <= nop;
					
				WHEN ld_dAn1 =>		-- Load with displacement d(An), d(PC)
					set(get_ea_now) <='1';
					setdisp <= '1';		-- 16-bit displacement
					setnextpass <= '1';
					
				WHEN ld_AnXn1 =>	-- Load with index d(An,Xn), d(PC,Xn)
					IF brief(8)='0' OR extAddr_Mode=0 OR (cpu(1)='0' AND extAddr_Mode=2) THEN
						-- 68000/010 addressing mode
						setdisp <= '1';		-- 8-bit displacement	
						setdispbyte <= '1';
						setstate <= "01";
						set(briefext) <= '1';
						next_micro_state <= ld_AnXn2;
					ELSE	
						-- 68020 full extension word
						IF brief(7)='1'THEN		-- Suppress base register
							set_suppress_base <= '1';
						ELSIF exec(dispouter)='1' THEN
							set(dispouter) <= '1';
						END IF;
						IF brief(5)='0' THEN -- No base displacement
							setstate <= "01";
						ELSE  -- Word base displacement
							IF brief(4)='1' THEN
								set(longaktion) <= '1'; -- Long base displacement
							END IF;
						END IF;
						next_micro_state <= ld_229_1;
					END IF;
					
				WHEN ld_AnXn2 =>
					set(get_ea_now) <='1';
					setdisp <= '1';		-- Add brief extension
					setnextpass <= '1';
					
			-- 68020 complex addressing modes
				WHEN ld_229_1 =>		-- (bd,An,Xn), (bd,PC,Xn)
					IF brief(5)='1' THEN    -- Base displacement present
						setdisp <= '1';		
					END IF;
					IF brief(6)='0' AND brief(2)='0' THEN -- Pre-index or index
						set(briefext) <= '1';
						setstate <= "01";
						IF brief(1 downto 0)="00" THEN
							next_micro_state <= ld_AnXn2;
						ELSE	
							next_micro_state <= ld_229_2;
						END IF;	
					ELSE
						IF brief(1 downto 0)="00" THEN
							set(get_ea_now) <='1';
							setnextpass <= '1';
						ELSE
							setstate <= "10";
							setaddrvalue <= '1';
							set(longaktion) <= '1';
							next_micro_state <= ld_229_3;
						END IF;
					END IF;
					
				WHEN ld_229_2 =>		-- Add index
					setdisp <= '1';		
					setstate <= "10";
					setaddrvalue <= '1';
					set(longaktion) <= '1';
					next_micro_state <= ld_229_3;
				
				WHEN ld_229_3 =>		-- Memory indirect
					set_suppress_base <= '1';
					set(dispouter) <= '1'; 	
					IF brief(1)='0' THEN -- No outer displacement
						setstate <= "01";
					ELSE  -- Word outer displacement
						IF brief(0)='1' THEN
							set(longaktion) <= '1'; -- Long outer displacement
						END IF;
					END IF;
					next_micro_state <= ld_229_4;
				
				WHEN ld_229_4 =>		-- Add outer displacement
					IF brief(1)='1' THEN  
						setdisp <= '1';	  
					END IF;
					IF brief(6)='0' AND brief(2)='1' THEN -- Post-index
						set(briefext) <= '1';
						setstate <= "01";
						next_micro_state <= ld_AnXn2;
					ELSE
						set(get_ea_now) <='1';
						setnextpass <= '1';
					END IF;
					
			-- Store operations with complex addressing				
				WHEN st_dAn1 =>		-- Store with displacement d(An)
					setstate <= "11";
					setdisp <= '1';		
					next_micro_state <= nop;
					
				WHEN st_AnXn1 =>	-- Store with index d(An,Xn)
					IF brief(8)='0' OR extAddr_Mode=0 OR (cpu(1)='0' AND extAddr_Mode=2) THEN
						setdisp <= '1';		
						setdispbyte <= '1';
						setstate <= "01";
						set(briefext) <= '1';
						next_micro_state <= st_AnXn2;
					ELSE	
						-- 68020 modes (similar to load)
						IF brief(7)='1'THEN		
							set_suppress_base <= '1';
						END IF;
						IF brief(5)='0' THEN 
							setstate <= "01";
						ELSE  
							IF brief(4)='1' THEN
								set(longaktion) <= '1'; 
							END IF;
						END IF;
						next_micro_state <= st_229_1;
					END IF;
					
				WHEN st_AnXn2 =>
					setstate <= "11";
					setdisp <= '1';		
					set(hold_dwr) <= '1';
					next_micro_state <= nop;
					
			-- 68020 store complex addressing (similar structure to load)				
				WHEN st_229_1 =>		
					IF brief(5)='1' THEN   
						setdisp <= '1';		
					END IF;
					IF brief(6)='0' AND brief(2)='0' THEN 
						set(briefext) <= '1';
						setstate <= "01";
						IF brief(1 downto 0)="00" THEN
							next_micro_state <= st_AnXn2;
						ELSE	
							next_micro_state <= st_229_2;
						END IF;	
					ELSE
						IF brief(1 downto 0)="00" THEN
							setstate <= "11";
							next_micro_state <= nop;
						ELSE
							set(hold_dwr) <= '1';
							setstate <= "10";
							set(longaktion) <= '1';
							next_micro_state <= st_229_3;
						END IF;
					END IF;
					
				WHEN st_229_2 =>		
					setdisp <= '1';		
					set(hold_dwr) <= '1';
					setstate <= "10";
					set(longaktion) <= '1';
					next_micro_state <= st_229_3;
				
				WHEN st_229_3 =>		
					set(hold_dwr) <= '1';
					set_suppress_base <= '1';
					set(dispouter) <= '1'; 	
					IF brief(1)='0' THEN 
						setstate <= "01";
					ELSE  
						IF brief(0)='1' THEN
							set(longaktion) <= '1'; 
						END IF;
					END IF;
					next_micro_state <= st_229_4;
				
				WHEN st_229_4 =>		
					set(hold_dwr) <= '1';
					IF brief(1)='1' THEN  
						setdisp <= '1';	  
					END IF;
					IF brief(6)='0' AND brief(2)='1' THEN 
						set(briefext) <= '1';
						setstate <= "01";
						next_micro_state <= st_AnXn2;
					ELSE
						setstate <= "11";
						next_micro_state <= nop;
					END IF;
					
			-- Branch operations				
				WHEN bra1 =>		-- Bcc
					IF exe_condition='1' THEN
						TG68_PC_brw <= '1';	
						next_micro_state <= nop;
						if long_start='0' then
							skipFetch <= '1'; -- Can't skip fetch for Bcc.L
						end if;
					END IF;
					
				WHEN bsr1 =>		-- BSR with 8-bit displacement
					TG68_PC_brw <= '1';	
					next_micro_state <= nop;
					
				WHEN bsr2 =>		-- BSR with 16/32-bit displacement
					IF long_start='0' THEN	
						TG68_PC_brw <= '1';	
						skipFetch <= '1';	-- Can't skip fetch for BSR.L
					END IF;
					set(longaktion) <= '1';
					writePC <= '1';
					setstate <= "11";
					next_micro_state <= nopnop;
					setstackaddr <='1';
					
				WHEN nopnop =>		-- Double NOP for timing
					next_micro_state <= nop;

				WHEN dbcc1 =>		-- DBcc
					IF exe_condition='0' THEN		-- Condition false, decrement and branch
						Regwrena_now <= '1';
						IF c_out(1)='1' THEN		-- Counter = -1, fall through
							skipFetch <= '1';				
							next_micro_state <= nop;
							TG68_PC_brw <= '1';	
						END IF;	
					END IF;

			-- CHK2/CMP2 operations (68020+)
				WHEN chk20 =>			-- Compare with lower bound
					set(ea_data_OP1) <= '1';
					set(addsub) <= '1';
					set(alu_exec) <= '1';
					set(alu_setFlags) <= '1';
					setstate <="01";
					next_micro_state <= chk21;
					
				WHEN chk21 =>			-- Compare with upper bound
					dest_2ndHbits <= '1';
					IF sndOPC(15)='1' THEN		-- Dn vs An register
						set_datatype <="10";	
						dest_LDRareg <= '1';
						IF opcode(10 downto 9)="00" THEN	-- Byte operation
							set(opcEXTB) <= '1';
						END IF;
					END IF;
					set(addsub) <= '1';
					set(alu_exec) <= '1';
					set(alu_setFlags) <= '1';
					setstate <="01";
					next_micro_state <= chk22;
					
				WHEN chk22 =>			-- Final check
					dest_2ndHbits <= '1';
					set(ea_data_OP2) <= '1';
					IF sndOPC(15)='1' THEN
						set_datatype <="10";	
						dest_LDRareg <= '1';
					END IF;
					set(addsub) <= '1';
					set(alu_exec) <= '1';
					set(opcCHK2) <= '1';
					set(opcEXTB) <= exec(opcEXTB);
					IF sndOPC(11)='1' THEN		-- CHK2 (not CMP2)
						setstate <="01";
						next_micro_state <= chk23;
					END IF;
					
				WHEN chk23 =>
						setstate <="01";
						next_micro_state <= chk24;
						
				WHEN chk24 =>
					IF Flags(0)='1'THEN		-- Out of bounds
						trapmake <= '1';
					END IF;
					
			-- CAS operations (68020+)
				WHEN cas1 =>
						setstate <="01";
						next_micro_state <= cas2;
						
				WHEN cas2 =>
					source_2ndMbits <= '1';
					IF Flags(2)='1'THEN		-- Compare matched
						setstate<="11";
						set(write_reg) <= '1';
						set(restore_ADDR) <= '1';
						next_micro_state <= nop;
					ELSE
						set(Regwrena) <= '1';
						set(ea_data_OP2) <='1';
						dest_2ndLbits <= '1';
						set(alu_move) <= '1';
					END IF;
					
			-- CAS2 operations (68020+)
				WHEN cas21 =>
					dest_2ndHbits <= '1';
					dest_LDRareg <= sndOPC(15);
					set(get_ea_now) <='1';
					next_micro_state <= cas22;
					
				WHEN cas22 =>
					setstate <= "01";
					source_2ndLbits <= '1';
					set(ea_data_OP1) <= '1';
					set(addsub) <= '1';
					set(alu_exec) <= '1';
					set(alu_setFlags) <= '1';
					next_micro_state <= cas23;
					
				WHEN cas23 =>
					dest_LDRHbits <= '1';
					set(get_ea_now) <='1';
					next_micro_state <= cas24;
					
				WHEN cas24 =>
					IF Flags(2)='1'THEN
						set(alu_setFlags) <= '1';
					END IF;
					setstate <="01";
					set(hold_dwr) <= '1';
					source_LDRLbits <= '1';
					set(ea_data_OP1) <= '1';
					set(addsub) <= '1';
					set(alu_exec) <= '1';
					next_micro_state <= cas25;
					
				WHEN cas25 =>
					setstate <= "01";
					set(hold_dwr) <= '1';
					next_micro_state <= cas26;
					
				WHEN cas26 =>
					IF Flags(2)='1'THEN -- Both comparisons matched
						-- Write Update 1 to Destination 1
						source_2ndMbits <= '1';
						set(write_reg) <= '1';
						dest_2ndHbits <= '1';
						dest_LDRareg <= sndOPC(15);
						setstate <= "11";
						set(get_ea_now) <='1';
						next_micro_state <= cas27;
					ELSE		   			
						-- Write Destination 2 to Compare 2 first
						set(hold_dwr) <= '1';
						set(hold_OP2) <='1';
						dest_LDRLbits <= '1';
						set(alu_move) <= '1';
						set(Regwrena) <= '1';
						set(ea_data_OP2) <='1';
						next_micro_state <= cas28;
					END IF;
					
				WHEN cas27 =>				-- Write Update 2 to Destination 2
					source_LDRMbits <= '1';
					set(write_reg) <= '1';
					dest_LDRHbits <= '1';
					setstate <= "11";
					set(get_ea_now) <='1';
					next_micro_state <= nopnop;
					
				WHEN cas28 =>				-- Write Destination 1 to Compare 1
					dest_2ndLbits <= '1';
					set(alu_move) <= '1';
					set(Regwrena) <= '1';
					
			-- MOVEM operations
				WHEN movem1 =>		
					IF last_data_read(15 downto 0)/=X"0000" THEN	-- More registers to move
						setstate <="01";
						IF opcode(5 downto 3)="100" THEN	-- -(An) mode
							set(mem_addsub) <= '1';
							IF cpu(1)='1' THEN
								set(Regwrena) <= '1';	
							END IF;
						END IF;
						next_micro_state <= movem2;
					END IF;
					
				WHEN movem2 =>		
					IF movem_run='0' THEN		-- All registers processed
						setstate <="01";
					ELSE	
						set(movem_action) <= '1';
						set(mem_addsub) <= '1';
						next_micro_state <= movem2;
						IF opcode(10)='0' THEN		-- Memory to register
							setstate <="11";
							set(write_reg) <= '1';
						ELSE						-- Register to memory
							setstate <="10";
						END IF;
					END IF;	

				WHEN andi =>		-- ANDI/ORI/EORI/ADDI/SUBI/CMPI
					IF opcode(5 downto 4)/="00" THEN
						setnextpass <= '1';
					END IF;

			-- PACK/UNPACK operations (68020+)
				WHEN pack1 =>		-- PACK -(Ax),-(Ay)
					IF opcode(2 downto 0)="111" THEN
						set(use_SP) <= '1';
					END IF;
					set(hold_ea_data) <= '1';	
					set(update_ld) <= '1';
					setstate <= "10";
					set(presub) <= '1';
					next_micro_state <= pack2;
					dest_areg <= '1';				
					
				WHEN pack2 =>	
					IF opcode(11 downto 9)="111" THEN
						set(use_SP) <= '1';
					END IF;
					set(hold_ea_data) <= '1';	
					set_direct_data <= '1';
					IF opcode(7 downto 6) = "01" THEN	-- PACK
						datatype <= "00";		-- Byte
					ELSE								-- UNPACK
						datatype <= "01";		-- Word
					END IF;
					set(presub) <= '1';
					dest_hbits <= '1'; 
					dest_areg <= '1';
					setstate <= "10";
					next_micro_state <= pack3;
					
				WHEN pack3 =>	
					skipFetch <= '1';
					
			-- BCD memory operations
				WHEN op_AxAy =>		-- ABCD/SBCD/ADDX/SUBX -(Ax),-(Ay)
					IF opcode(11 downto 9)="111" THEN
						set(use_SP) <= '1';
					END IF;
					set_direct_data <= '1';
					set(presub) <= '1';
					dest_hbits <= '1'; 
					dest_areg <= '1';
					setstate <= "10";

				WHEN cmpm =>		-- CMPM (Ay)+,(Ax)+
					IF opcode(11 downto 9)="111" THEN
						set(use_SP) <= '1';
					END IF;
					set_direct_data <= '1';
					set(postadd) <= '1';
					dest_hbits <= '1'; 
					dest_areg <= '1';
					setstate <= "10";
					
			-- LINK/UNLK operations
				WHEN link1 =>		-- LINK
					setstate <="11";
					source_areg <= '1';
					set(opcMOVE) <= '1';
					set(Regwrena) <= '1';
					next_micro_state <= link2;
					
				WHEN link2 =>		-- LINK
					setstackaddr <='1';
					set(ea_data_OP2) <= '1';
					
				WHEN unlink1 =>		-- UNLK
					setstate <="10";
					setstackaddr <='1';
					set(postadd) <= '1';
					next_micro_state <= unlink2;
					
				WHEN unlink2 =>		-- UNLK
					set(ea_data_OP2) <= '1';
					
			-- Exception processing
				WHEN trap00 =>          -- TRAP format #2 (68010+)
					next_micro_state <= trap0;
					set(presub) <= '1';
					setstackaddr <='1';
					setstate <= "11";
					datatype <= "10";
					
				WHEN trap0 =>		-- TRAP/Exception entry
					set(presub) <= '1';
					setstackaddr <='1';
					setstate <= "11";
					IF use_VBR_Stackframe='1' THEN	-- 68010+
						set(writePC_add) <= '1';
						datatype <= "01";
						next_micro_state <= trap1;
					ELSE						-- 68000
						IF trap_interrupt='1' OR trap_trace='1' OR trap_berr='1' THEN
							writePC <= '1';
						END IF;
						datatype <= "10";
						next_micro_state <= trap2;
					END IF;

				WHEN trap1 =>		-- TRAP - push vector offset (68010+)
					IF trap_interrupt='1' OR trap_trace='1' THEN
						writePC <= '1';
					END IF;
					set(presub) <= '1';
					setstackaddr <='1';
					setstate <= "11";
					datatype <= "10";
					next_micro_state <= trap2;
					
				WHEN trap2 =>		-- TRAP - push PC
					set(presub) <= '1';
					setstackaddr <='1';
					setstate <= "11";
					datatype <= "01";
					writeSR <= '1';
					IF trap_berr='1' THEN
						next_micro_state <= trap4;	-- Bus error needs more info
					ELSE
						next_micro_state <= trap3;
					END IF;
					
				WHEN trap3 =>		-- TRAP - fetch vector
					set_vectoraddr <= '1';
					datatype <= "10";
					set(direct_delta) <= '1';	
					set(directPC) <= '1';
					setstate <= "10";
					next_micro_state <= nopnop;
					
			-- Bus error stack frame (68000 only)
				WHEN trap4 =>		-- TRAP - bus error extra info
					set(presub) <= '1';
					setstackaddr <='1';
					setstate <= "11";
					datatype <= "01";
					writeSR <= '1';		-- Instruction register
					next_micro_state <= trap5;
					
				WHEN trap5 =>		-- TRAP - bus error
					set(presub) <= '1';
					setstackaddr <='1';
					setstate <= "11";
					datatype <= "10";
					writeSR <= '1';		-- Access address
					next_micro_state <= trap6;
					
				WHEN trap6 =>		-- TRAP - bus error
					set(presub) <= '1';
					setstackaddr <='1';
					setstate <= "11";
					datatype <= "01";
					writeSR <= '1';		-- Access type and function code
					next_micro_state <= trap3;
					
			-- Return from exception - RTE
				WHEN rte1 =>		-- RTE - pop PC
					datatype <= "10";
					setstate <= "10";
					set(postadd) <= '1';
					setstackaddr <= '1';
					set(directPC) <= '1';	
					IF use_VBR_Stackframe='0' OR opcode(2)='1' THEN	-- 68000 or RTR
						set(update_FC) <= '1';
						set(direct_delta) <= '1';	
					END IF;
					next_micro_state <= rte2;
					
				WHEN rte2 =>		-- RTE - check for extended frame
					datatype <= "01";
					set(update_FC) <= '1';
					IF use_VBR_Stackframe='1' AND opcode(2)='0' THEN
						-- 68010+ reads stack frame format
						setstate <= "10";
						set(postadd) <= '1';
						setstackaddr <= '1';
						next_micro_state <= rte3;
					ELSE
						next_micro_state <= nop;
					END IF;
					
				when rte3 => -- RTE - wait for format word
					setstate <= "01"; 
					next_micro_state <= rte4;
					
				WHEN rte4 =>         -- RTE - check format
					-- Stack frame format #2?
					if last_data_in(15 downto 12)="0010" then
						-- Read another 32 bits 
						setstate <= "10"; 
						datatype <= "10"; 
						set(postadd) <= '1';
						setstackaddr <= '1';
						next_micro_state <= rte5;
					else
						datatype <= "01";
						next_micro_state <= nop;
					end if;
					
				WHEN rte5 =>            -- RTE - discard extra data
					next_micro_state <= nop;

				WHEN rtd1 =>		-- RTD - add displacement to SP
					next_micro_state <= rtd2;
					
				WHEN rtd2 =>		-- RTD
					setstackaddr <= '1';
					set(Regwrena) <= '1';
					
			-- MOVEC operations (68010+)
				WHEN movec1 =>		-- MOVEC
					set(briefext) <= '1';
					set_writePCbig <='1';
					-- Check for valid control register
					IF (brief(11 downto 0)=X"000" OR brief(11 downto 0)=X"001" OR brief(11 downto 0)=X"800" OR brief(11 downto 0)=X"801") OR 
					   (cpu(1)='1' AND (brief(11 downto 0)=X"002" OR brief(11 downto 0)=X"802" OR brief(11 downto 0)=X"803" OR brief(11 downto 0)=X"804")) THEN
						IF opcode(0)='0' THEN	-- From control register
							set(Regwrena) <= '1';
						END IF;
					ELSE
						trap_illegal <= '1';
						trapmake <= '1';
					END IF;
					
			-- MOVEP operations
				WHEN movep1 =>		-- MOVEP d(An) - first access
					setdisp <= '1';	
					set(mem_addsub) <= '1';	
					set(mem_byte) <= '1';		-- Force byte access
					set(OP1addr) <= '1';		
					IF opcode(6)='1' THEN		-- Long operation
						set(movepl) <= '1';
					END IF;
					IF opcode(7)='0' THEN		-- Memory to register
						setstate <= "10";
					ELSE						-- Register to memory
						setstate <= "11";
					END IF;
					next_micro_state <= movep2;
					
				WHEN movep2 =>		-- Second byte
					IF opcode(6)='1' THEN
						set(mem_addsub) <= '1';	
					    set(OP1addr) <= '1';		
					END IF;
					IF opcode(7)='0' THEN
						setstate <= "10";
					ELSE
						setstate <= "11";
					END IF;
					next_micro_state <= movep3;
					
				WHEN movep3 =>		-- Third byte (long only)
					IF opcode(6)='1' THEN
						set(mem_addsub) <= '1';	
					    set(OP1addr) <= '1';		
						set(mem_byte) <= '1';
						IF opcode(7)='0' THEN
							setstate <= "10";
						ELSE
							setstate <= "11";
						END IF;
						next_micro_state <= movep4;
					ELSE	
						datatype <= "01";		-- Word complete
					END IF;
					
				WHEN movep4 =>		-- Fourth byte (long only)
					IF opcode(7)='0' THEN
						setstate <= "10";
					ELSE
						setstate <= "11";
					END IF;
					next_micro_state <= movep5;
					
				WHEN movep5 =>		
					datatype <= "10";		-- Long complete
					
			-- Multiply operations
				WHEN mul1	=>		-- MULU/MULS - initialize
					IF opcode(15)='1' OR MUL_Mode=0 THEN
						set_rot_cnt <= "001110";	-- 16-bit: 14 cycles
					ELSE
						set_rot_cnt <= "011110";	-- 32-bit: 30 cycles
					END IF;
					setstate <="01";
					next_micro_state <= mul2;
					
				WHEN mul2	=>		-- MULU/MULS - iterate
					setstate <="01";
					IF rot_cnt="00001" THEN
						next_micro_state <= mul_end1;
					ELSE	
						next_micro_state <= mul2;
					END IF;
					
				WHEN mul_end1	=>		-- MULU/MULS - store result
					IF opcode(15)='0' THEN		-- Long multiply
						set(hold_OP2) <= '1';
					END IF;
					datatype <= "10";
					set(opcMULU) <= '1';
					IF opcode(15)='0' AND (MUL_Mode=1 OR MUL_Mode=2) THEN
						dest_2ndHbits <= '1';
						set(write_lowlong) <= '1';
						IF sndOPC(10)='1' THEN		-- 64-bit result
							setstate <="01";
							next_micro_state <= mul_end2;
						END IF;	
						set(Regwrena) <= '1';
					END IF;
					datatype <= "10";
					
				WHEN mul_end2	=>		-- MULU/MULS - store high long
					dest_2ndLbits <= '1';
					set(write_reminder) <= '1';
					set(Regwrena) <= '1';
					set(opcMULU) <= '1';

			-- Division operations
				WHEN div1	=>		-- DIVU/DIVS - check divisor
					setstate <="01";
					next_micro_state <= div2;
					
				WHEN div2	=>		-- DIVU/DIVS - check for divide by zero
					IF (OP2out(31 downto 16)=x"0000" OR opcode(15)='1' OR DIV_Mode=0) AND OP2out(15 downto 0)=x"0000" THEN		
						set_Z_error <= '1';	-- Division by zero
					ELSE
						next_micro_state <= div3;
					END IF;
					set(ld_rot_cnt) <= '1'; 
					setstate <="01";
					
				WHEN div3	=>		-- DIVU/DIVS - initialize
					IF opcode(15)='1' OR DIV_Mode=0 THEN
						set_rot_cnt <= "001101";	-- 16-bit: 13 cycles
					ELSE
						set_rot_cnt <= "011101";	-- 32-bit: 29 cycles
					END IF;
					setstate <="01";
					next_micro_state <= div4;
					
				WHEN div4	=>		-- DIVU/DIVS - iterate
					setstate <="01";
					IF rot_cnt="00001" THEN
						next_micro_state <= div_end1;
					ELSE	
						next_micro_state <= div4;
					END IF;
					
				WHEN div_end1	=>		-- DIVU/DIVS - store quotient
					IF z_error='0' AND set_V_Flag='0' THEN
						set(Regwrena) <= '1';
					END IF;
					IF opcode(15)='0' AND (DIV_Mode=1 OR DIV_Mode=2) THEN
						dest_2ndLbits <= '1';
						set(write_reminder) <= '1';
						next_micro_state <= div_end2;
						setstate <="01";
					END IF;
					set(opcDIVU) <= '1';
					datatype <= "10";
					
				WHEN div_end2	=>		-- DIVU/DIVS - store remainder
					IF exec(Regwrena)='1' THEN
						set(Regwrena) <= '1';
					ELSE	
						set(no_Flags) <= '1';
					END IF;
					dest_2ndHbits <= '1';
					set(opcDIVU) <= '1';
					
			-- Rotation with register count
				WHEN rota1	=>
					IF OP2out(5 downto 0)/="000000" THEN
						set_rot_cnt <= OP2out(5 downto 0);
					ELSE
						set_exec(rot_nop) <= '1';	-- Count of 0 means no rotation
					END IF;
					
			-- Bit field
				WHEN bf1 =>
					setstate <="10";
	
				WHEN OTHERS => NULL;
			END CASE;
	END PROCESS;

-----------------------------------------------------------------------------
-- MOVEC Control Register Access
-----------------------------------------------------------------------------
  process (clk, SFC, DFC, VBR, CACR, brief)
  begin
	-- MOVEC control register codes:
	-- 000 = SFC (Source Function Code)
	-- 001 = DFC (Destination Function Code)  
	-- 002 = CACR (Cache Control Register) - 68020+
	-- 800 = USP (User Stack Pointer)
	-- 801 = VBR (Vector Base Register) - 68010+
	-- 802 = CAAR (Cache Address Register) - 68020+
	-- 803 = MSP (Master Stack Pointer) - 68020+
	-- 804 = ISP (Interrupt Stack Pointer) - 68020+
	
	if rising_edge(clk) then
	  if Reset = '1' then
		VBR <= (others => '0');
		CACR <= (others => '0');
	  elsif clkena_lw = '1' and exec(movec_wr) = '1' then
		case brief(11 downto 0) is
		  when X"000" => SFC <= reg_QA(2 downto 0); 	-- SFC
		  when X"001" => DFC <= reg_QA(2 downto 0); 	-- DFC
		  when X"002" => CACR <= reg_QA(3 downto 0); 	-- CACR (68020+)
		  when X"800" => NULL; 							-- USP handled elsewhere
		  when X"801" => VBR <= reg_QA; 				-- VBR (68010+)
		  when X"802" => NULL; 							-- CAAR not implemented
		  when X"803" => NULL; 							-- MSP not implemented
		  when X"804" => NULL; 							-- ISP not implemented
		  when others => NULL;
		end case;
	  end if;
	end if;

	-- MOVEC read multiplexer
	movec_data <= (others => '0');
	case brief(11 downto 0) is
		when X"000" => movec_data <= "00000000000000000000000000000" & SFC;
		when X"001" => movec_data <= "00000000000000000000000000000" & DFC;
	  when X"002" => movec_data <= "0000000000000000000000000000" & (CACR AND "0011");
	  when X"801" => movec_data <= VBR;
	  when others => NULL;
	end case;
  end process;

  CACR_out <= CACR;
  VBR_out <= VBR;
  
-----------------------------------------------------------------------------
-- Condition Code Evaluation
-----------------------------------------------------------------------------
PROCESS (exe_opcode, Flags)
	BEGIN
		-- Evaluate condition codes for Bcc, DBcc, Scc, TRAPcc
		CASE exe_opcode(11 downto 8) IS
			WHEN X"0" => exe_condition <= '1';								-- True (BRA, BSR)
			WHEN X"1" => exe_condition <= '0';								-- False (BSR variant)
			WHEN X"2" => exe_condition <=  NOT Flags(0) AND NOT Flags(2);	-- HI (C=0 AND Z=0)
			WHEN X"3" => exe_condition <= Flags(0) OR Flags(2);			-- LS (C=1 OR Z=1)
			WHEN X"4" => exe_condition <= NOT Flags(0);					-- CC/HS (C=0)
			WHEN X"5" => exe_condition <= Flags(0);						-- CS/LO (C=1)
			WHEN X"6" => exe_condition <= NOT Flags(2);					-- NE (Z=0)
			WHEN X"7" => exe_condition <= Flags(2);						-- EQ (Z=1)
			WHEN X"8" => exe_condition <= NOT Flags(1);					-- VC (V=0)
			WHEN X"9" => exe_condition <= Flags(1);						-- VS (V=1)
			WHEN X"a" => exe_condition <= NOT Flags(3);					-- PL (N=0)
			WHEN X"b" => exe_condition <= Flags(3);						-- MI (N=1)
			WHEN X"c" => exe_condition <= (Flags(3) AND Flags(1)) OR (NOT Flags(3) AND NOT Flags(1));		-- GE (N=V)
			WHEN X"d" => exe_condition <= (Flags(3) AND NOT Flags(1)) OR (NOT Flags(3) AND Flags(1));		-- LT (N!=V)
			WHEN X"e" => exe_condition <= (Flags(3) AND Flags(1) AND NOT Flags(2)) OR (NOT Flags(3) AND NOT Flags(1) AND NOT Flags(2));	-- GT (N=V AND Z=0)
			WHEN X"f" => exe_condition <= (Flags(3) AND NOT Flags(1)) OR (NOT Flags(3) AND Flags(1)) OR Flags(2);	-- LE (N!=V OR Z=1)
			WHEN OTHERS => NULL;
		END CASE;
	END PROCESS;
	
-----------------------------------------------------------------------------
-- MOVEM Register Selection Logic
-----------------------------------------------------------------------------
PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF clkena_lw='1' THEN
				movem_actiond <= exec(movem_action); 
				IF decodeOPC='1' THEN
					-- Load register mask
					sndOPC <= data_read(15 downto 0);
				ELSIF exec(movem_action)='1' OR set(movem_action) ='1' THEN
					-- Clear bit for processed register
					CASE movem_regaddr IS
						WHEN "0000" => sndOPC(0)  <= '0';
						WHEN "0001" => sndOPC(1)  <= '0';
						WHEN "0010" => sndOPC(2)  <= '0';
						WHEN "0011" => sndOPC(3)  <= '0';
						WHEN "0100" => sndOPC(4)  <= '0';
						WHEN "0101" => sndOPC(5)  <= '0';
						WHEN "0110" => sndOPC(6)  <= '0';
						WHEN "0111" => sndOPC(7)  <= '0';
						WHEN "1000" => sndOPC(8)  <= '0';
						WHEN "1001" => sndOPC(9)  <= '0';
						WHEN "1010" => sndOPC(10) <= '0';
						WHEN "1011" => sndOPC(11) <= '0';
						WHEN "1100" => sndOPC(12) <= '0';
						WHEN "1101" => sndOPC(13) <= '0';
						WHEN "1110" => sndOPC(14) <= '0';
						WHEN "1111" => sndOPC(15) <= '0';
						WHEN OTHERS => NULL;
					END CASE;
				END IF;
			END IF;
		END IF;
	END PROCESS;
	
-- Priority encoder for MOVEM register selection
PROCESS (sndOPC, movem_mux)
	BEGIN
		movem_regaddr <="0000";
		movem_run <= '1';
		-- Find first set bit (priority encoder)
		IF sndOPC(3 downto 0)="0000" THEN
			IF sndOPC(7 downto 4)="0000" THEN
				movem_regaddr(3) <= '1';
				IF sndOPC(11 downto 8)="0000" THEN
					IF sndOPC(15 downto 12)="0000" THEN
						movem_run <= '0';		-- No more registers
					END IF;
					movem_regaddr(2) <= '1';
					movem_mux <= sndOPC(15 downto 12);
				ELSE
					movem_mux <= sndOPC(11 downto 8);
				END IF;
			ELSE
				movem_mux <= sndOPC(7 downto 4);
				movem_regaddr(2) <= '1';
			END IF;
		ELSE
			movem_mux <= sndOPC(3 downto 0);
		END IF;
		-- Encode bit position within nibble
		IF movem_mux(1 downto 0)="00" THEN
			movem_regaddr(1) <= '1';
			IF movem_mux(2)='0' THEN
				movem_regaddr(0) <= '1';
			END IF;	
		ELSE		
			IF movem_mux(0)='0' THEN
				movem_regaddr(0) <= '1';
			END IF;	
		END  IF;
	END PROCESS;
END;
