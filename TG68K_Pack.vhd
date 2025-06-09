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
library IEEE;
use IEEE.std_logic_1164.all;

-- TG68K_Pack: Package containing shared type definitions and constants
-- Used throughout the TG68K processor core implementation
package TG68K_Pack is

	-------------------------------------------------------------------------------
	-- Microcode State Machine States
	-- These states control the execution sequencer for complex instructions
	-------------------------------------------------------------------------------
	type micro_states is (
		-- Basic states
		idle,        -- No operation in progress, ready for next instruction
		nop,         -- No operation cycle
		
		-- Memory load states (nn = next word)
		ld_nn,       -- Load next instruction/operand word
		st_nn,       -- Store next word
		
		-- Address register indirect modes
		ld_dAn1,     -- Load using (An) addressing
		ld_AnXn1,    -- Load using (An,Xn) addressing - phase 1
		ld_AnXn2,    -- Load using (An,Xn) addressing - phase 2
		st_dAn1,     -- Store using (An) addressing
		
		-- Address register with displacement and index
		ld_AnXnbd1,  -- Load (d8,An,Xn) or ([bd,An,Xn],od) - phase 1
		ld_AnXnbd2,  -- Load (d8,An,Xn) or ([bd,An,Xn],od) - phase 2
		ld_AnXnbd3,  -- Load (d8,An,Xn) or ([bd,An,Xn],od) - phase 3
		
		-- 68020 full extension word modes (format 229)
		ld_229_1, ld_229_2, ld_229_3, ld_229_4,   -- Load with full extension
		st_229_1, st_229_2, st_229_3, st_229_4,   -- Store with full extension
		
		-- More addressing modes
		st_AnXn1, st_AnXn2,  -- Store using (An,Xn) addressing
		
		-- Branch and subroutine operations
		bra1,        -- Branch instruction
		bsr1, bsr2,  -- Branch to subroutine
		
		-- Special instruction sequences
		nopnop,      -- Double NOP (used for timing)
		dbcc1,       -- DBcc (decrement and branch) instruction
		
		-- MOVEM (move multiple registers)
		movem1, movem2, movem3,  -- MOVEM instruction phases
		
		-- Immediate operations
		andi,        -- AND immediate (used for ANDI to CCR/SR)
		
		-- BCD operations
		pack1, pack2, pack3,     -- PACK BCD instruction phases
		
		-- Register operations
		op_AxAy,     -- Operation between address registers
		cmpm,        -- Compare memory (CMPM instruction)
		
		-- Stack frame operations
		link1, link2,            -- LINK instruction phases
		unlink1, unlink2,        -- UNLINK instruction phases
		
		-- Exception processing
		int1, int2, int3, int4,  -- Interrupt processing phases
		rte1, rte2, rte3, rte4, rte5,  -- Return from exception phases
		rtd1, rtd2,              -- Return and deallocate
		
		-- Trap and exception states
		trap00,      -- Reset vector fetch
		trap0,       -- Trap setup
		trap1, trap2, trap3, trap4, trap5, trap6,  -- Trap processing phases
		
		-- Compare and swap operations
		cas1, cas2,  -- CAS instruction setup
		cas21, cas22, cas23, cas24, cas25, cas26, cas27, cas28,  -- CAS execution phases
		
		-- Check operations
		chk20, chk21, chk22, chk23, chk24,  -- CHK2/CMP2 instruction phases
		
		-- Special move operations
		movec1,      -- MOVEC (move control register)
		movep1, movep2, movep3, movep4, movep5,  -- MOVEP instruction phases
		
		-- Rotation and bit field operations
		rota1,       -- Rotation setup
		bf1,         -- Bit field instruction
		
		-- Multiplication states
		mul1, mul2,  -- Multiplication setup and execution
		mul_end1, mul_end2,  -- Multiplication completion
		
		-- Division states
		div1, div2, div3, div4,  -- Division execution phases
		div_end1, div_end2       -- Division completion
	);
	
	-------------------------------------------------------------------------------
	-- Execution Control Signals
	-- These constants define bit positions in the exec control vector
	-- Each bit enables a specific operation or data path in the ALU/CPU
	-------------------------------------------------------------------------------
	
	-- Basic ALU operations
	constant opcMOVE			: integer := 0;  -- MOVE instruction (copy data)
	constant opcMOVEQ			: integer := 1;  -- MOVEQ (move quick - 8-bit immediate)
	constant opcMOVESR		: integer := 2;  -- MOVE from SR/CCR
	constant opcADD			: integer := 3;  -- ADD/ADDA/ADDI/ADDQ instructions
	constant opcADDQ			: integer := 4;  -- ADDQ specific flag
	constant opcOR				: integer := 5;  -- OR/ORI instructions
	constant opcAND			: integer := 6;  -- AND/ANDI instructions
	constant opcEOR			: integer := 7;  -- EOR/EORI instructions
	constant opcCMP			: integer := 8;  -- CMP/CMPA/CMPI instructions
	constant opcROT			: integer := 9;  -- Rotation/shift operations
	constant opcCPMAW			: integer := 10; -- CMPA.W (word compare to address register)
	constant opcEXT			: integer := 11; -- EXT (sign extend) instruction
	constant opcABCD			: integer := 12; -- ABCD (BCD add) instruction
	constant opcSBCD			: integer := 13; -- SBCD (BCD subtract) instruction
	constant opcBITS			: integer := 14; -- Bit operations (BTST, BCHG, BCLR, BSET)
	constant opcSWAP			: integer := 15; -- SWAP (exchange register halves)
	constant opcScc			: integer := 16; -- Scc (set on condition) instructions
	
	-- SR/CCR operations
	constant andiSR			: integer := 17; -- ANDI to SR
	constant eoriSR			: integer := 18; -- EORI to SR
	constant oriSR				: integer := 19; -- ORI to SR
	
	-- Multiplication and division
	constant opcMULU			: integer := 20; -- MULU/MULS instructions
	constant opcDIVU			: integer := 21; -- DIVU/DIVS instructions
	
	-- Addressing and control
	constant dispouter		: integer := 22; -- Displacement outer (68020 addressing)
	constant rot_nop			: integer := 23; -- Rotation no-operation (count=0)
	constant ld_rot_cnt		: integer := 24; -- Load rotation count
	constant writePC_add		: integer := 25; -- Write PC with displacement
	constant ea_data_OP1		: integer := 26; -- EA data to operand 1
	constant ea_data_OP2		: integer := 27; -- EA data to operand 2
	constant use_XZFlag		: integer := 28; -- Use extended zero flag
	constant get_bfoffset	: integer := 29; -- Get bit field offset
	constant save_memaddr	: integer := 30; -- Save memory address
	constant opcCHK			: integer := 31; -- CHK (check bounds) instruction
	
	-- Control register operations
	constant movec_rd			: integer := 32; -- MOVEC read
	constant movec_wr			: integer := 33; -- MOVEC write
	constant Regwrena			: integer := 34; -- Register write enable
	constant update_FC		: integer := 35; -- Update function codes
	constant linksp			: integer := 36; -- LINK using stack pointer
	constant movepl			: integer := 37; -- MOVEP long operation
	constant update_ld		: integer := 38; -- Update load
	constant OP1addr			: integer := 39; -- Operand 1 address mode
	constant write_reg		: integer := 40; -- Write to register
	constant changeMode		: integer := 41; -- Change CPU mode (user/supervisor)
	
	-- Effective address operations
	constant ea_build			: integer := 42; -- Build effective address
	constant trap_chk			: integer := 43; -- Trap on CHK exception
	constant store_ea_data	: integer := 44; -- Store EA data
	constant addrlong			: integer := 45; -- Long word address operation
	
	-- Address register updates
	constant postadd			: integer := 46; -- Post-increment addressing
	constant presub			: integer := 47; -- Pre-decrement addressing
	constant subidx			: integer := 48; -- Subtract index
	
	-- Flag and condition code control
	constant no_Flags			: integer := 49; -- Don't update flags
	constant use_SP			: integer := 50; -- Use stack pointer
	constant to_CCR			: integer := 51; -- Move to CCR
	constant to_SR				: integer := 52; -- Move to SR
	
	-- Operand control
	constant OP2out_one		: integer := 53; -- Force operand 2 to 1
	constant OP1out_zero		: integer := 54; -- Force operand 1 to 0
	constant mem_addsub		: integer := 55; -- Memory address add/subtract
	constant addsub			: integer := 56; -- ALU add/subtract operation
	
	-- Direct register access
	constant directPC			: integer := 57; -- Direct PC access
	constant direct_delta	: integer := 58; -- Direct delta value
	constant directSR			: integer := 59; -- Direct SR access
	constant directCCR		: integer := 60; -- Direct CCR access
	constant exg				: integer := 61; -- EXG (exchange) instruction
	
	-- EA timing control
	constant get_ea_now		: integer := 62; -- Get EA immediately
	constant ea_to_pc			: integer := 63; -- EA result to PC
	constant hold_dwr			: integer := 64; -- Hold data write
	
	-- Stack pointer operations
	constant to_USP			: integer := 65; -- Move to user stack pointer
	constant from_USP			: integer := 66; -- Move from user stack pointer
	
	-- Extended operations
	constant write_lowlong	: integer := 67; -- Write lower longword (64-bit ops)
	constant write_reminder	: integer := 68; -- Write remainder (division)
	constant movem_action	: integer := 69; -- MOVEM in progress
	constant briefext			: integer := 70; -- Brief extension word
	constant get_2ndOPC		: integer := 71; -- Get second opcode word
	constant mem_byte			: integer := 72; -- Memory byte operation
	constant longaktion		: integer := 73; -- Long word operation
	constant opcRESET			: integer := 74; -- RESET instruction
	
	-- Bit field operations
	constant opcBF				: integer := 75; -- Bit field instruction
	constant opcBFwb			: integer := 76; -- Bit field writeback
	
	-- BCD pack/unpack
	constant opcPACK			: integer := 77; -- PACK instruction
	constant opcUNPACK		: integer := 78; -- UNPK instruction
	
	-- EA data handling
	constant hold_ea_data		: integer := 79; -- Hold EA data
	constant store_ea_packdata	: integer := 80; -- Store packed EA data
	
	-- Barrel shifter
	constant exec_BS				: integer := 81; -- Execute barrel shift
	
	-- Miscellaneous
	constant hold_OP2				: integer := 82; -- Hold operand 2
	constant restore_ADDR		: integer := 83; -- Restore address
	constant alu_exec				: integer := 84; -- ALU execute
	constant alu_move				: integer := 85; -- ALU move operation
	constant alu_setFlags		: integer := 86; -- ALU set flags
	constant opcCHK2				: integer := 87; -- CHK2 instruction
	constant opcEXTB				: integer := 88; -- EXTB (extend byte to long)

	-- Last bit position in exec control vector
	constant lastOpcBit			: integer := 88;

	-------------------------------------------------------------------------------
	-- ALU Component Declaration
	-- The main arithmetic/logic unit of the processor
	-------------------------------------------------------------------------------
	component TG68K_ALU
	generic(
		-- Multiplication configuration
		MUL_Mode :integer;			--0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no MUL  
		MUL_Hardware :integer;		--0=>no (iterative), 1=>yes (combinatorial multiplier)
		-- Division configuration
		DIV_Mode :integer;			--0=>16Bit, 1=>32Bit, 2=>switchable with CPU(1), 3=>no DIV
		-- Barrel shifter configuration  
		BarrelShifter :integer		--0=>no, 1=>yes, 2=>switchable with CPU(1)  
		);
	port(
		-- Clock and control
		clk						: in std_logic;
		Reset						: in std_logic;
		CPU						: in std_logic_vector(1 downto 0):="00";  -- 00->68000  01->68010  11->68020
		clkena_lw				: in std_logic:='1';
		
		-- Instruction decode inputs
		execOPC					: in bit;                    -- Execute opcode
		decodeOPC				: in bit;                    -- Decode opcode
		exe_condition			: in std_logic;              -- Condition true for Scc
		exec_tas					: in std_logic;              -- TAS instruction
		long_start				: in bit;                    -- Long operation start
		non_aligned				: in std_logic;              -- Non-aligned access
		check_aligned			: in std_logic;              -- Check alignment
		movem_presub			: in bit;                    -- MOVEM predecrement
		set_stop					: in bit;                    -- STOP instruction
		Z_error					: in bit;                    -- Division by zero
		rot_bits					: in std_logic_vector(1 downto 0);  -- Rotation type
		exec						: in bit_vector(lastOpcBit downto 0);  -- Execution control
		
		-- Operand inputs
		OP1out					: in std_logic_vector(31 downto 0);  -- Operand 1
		OP2out					: in std_logic_vector(31 downto 0);  -- Operand 2
		reg_QA					: in std_logic_vector(31 downto 0);  -- Register A
		reg_QB					: in std_logic_vector(31 downto 0);  -- Register B
		
		-- Instruction information
		opcode					: in std_logic_vector(15 downto 0);  -- Current opcode
		exe_opcode				: in std_logic_vector(15 downto 0);  -- Executing opcode
		exe_datatype			: in std_logic_vector(1 downto 0);   -- Data size
		sndOPC					: in std_logic_vector(15 downto 0);  -- Second opcode word
		last_data_read			: in std_logic_vector(15 downto 0);  -- Previous data
		data_read				: in std_logic_vector(15 downto 0);  -- Current data
		FlagsSR					: in std_logic_vector(7 downto 0);   -- Status register
		micro_state				: in micro_states;                    -- Microcode state
		
		-- Bit field parameters
		bf_ext_in				: in std_logic_vector(7 downto 0);   -- BF extension in
		bf_ext_out				: out std_logic_vector(7 downto 0);  -- BF extension out
		bf_shift					: in std_logic_vector(5 downto 0);   -- BF shift amount
		bf_width					: in std_logic_vector(5 downto 0);   -- BF width
		bf_ffo_offset			: in std_logic_vector(31 downto 0);  -- BFFFO offset
		bf_loffset				: in std_logic_vector(4 downto 0);   -- BF left offset

		-- Outputs
		set_V_Flag				: buffer bit;                         -- Set V flag
		Flags						: buffer std_logic_vector(7 downto 0);  -- CCR flags
		c_out						: buffer std_logic_vector(2 downto 0);  -- Carry outputs
		addsub_q					: buffer std_logic_vector(31 downto 0); -- Add/sub result
		ALUout					: out std_logic_vector(31 downto 0)     -- ALU result
	);
	end component;

end;
