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

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;

-- TG68K_ALU: Arithmetic Logic Unit for the TG68K processor core
-- Implements all arithmetic, logical, shift, and bit manipulation operations
entity TG68K_ALU is
generic(
		-- Multiplication mode: 0=16bit only, 1=32bit only, 2=switchable, 3=no MUL
		MUL_Mode : integer;			--0=>16Bit,	1=>32Bit,	2=>switchable with CPU(1),	3=>no MUL,  
		-- Hardware multiplier: 0=iterative, 1=combinatorial multiplier
		MUL_Hardware : integer;		--0=>no,		1=>yes,  
		-- Division mode: 0=16bit only, 1=32bit only, 2=switchable, 3=no DIV
		DIV_Mode : integer;			--0=>16Bit,	1=>32Bit,	2=>switchable with CPU(1),	3=>no DIV,  
		-- Barrel shifter: 0=no, 1=yes, 2=switchable
		BarrelShifter :integer		--0=>no,		1=>yes,		2=>switchable with CPU(1)  
		);
	port(clk						: in std_logic;
		Reset						: in std_logic;
		clkena_lw				: in std_logic:='1';
		CPU						: in std_logic_vector(1 downto 0):="00";  -- 00->68000  01->68010  11->68020(only some parts - yet)
		execOPC					: in bit;
		decodeOPC				: in bit;
		exe_condition			: in std_logic;
		exec_tas					: in std_logic;
		long_start				: in bit;
		non_aligned				: in std_logic;
		check_aligned			: in std_logic;
		movem_presub			: in bit;
		set_stop					: in bit;
		Z_error 					: in bit;
		rot_bits					: in std_logic_vector(1 downto 0);
		exec						: in bit_vector(lastOpcBit downto 0);
		OP1out					: in std_logic_vector(31 downto 0);
		OP2out					: in std_logic_vector(31 downto 0);
		reg_QA					: in std_logic_vector(31 downto 0);
		reg_QB					: in std_logic_vector(31 downto 0);
		opcode					: in std_logic_vector(15 downto 0);
		exe_opcode				: in std_logic_vector(15 downto 0);
		exe_datatype			: in std_logic_vector(1 downto 0);
		sndOPC					: in std_logic_vector(15 downto 0);
		last_data_read			: in std_logic_vector(15 downto 0);
		data_read				: in std_logic_vector(15 downto 0);
		FlagsSR					: in std_logic_vector(7 downto 0);
		micro_state				: in micro_states;  
		bf_ext_in				: in std_logic_vector(7 downto 0);
		bf_ext_out				: out std_logic_vector(7 downto 0);
		bf_shift					: in std_logic_vector(5 downto 0);
		bf_width					: in std_logic_vector(5 downto 0);
		bf_ffo_offset			: in std_logic_vector(31 downto 0);
		bf_loffset				: in std_logic_vector(4 downto 0);

		set_V_Flag				: buffer bit;
		Flags						: buffer std_logic_vector(7 downto 0);
		c_out						: buffer std_logic_vector(2 downto 0);
		addsub_q					: buffer std_logic_vector(31 downto 0);
		ALUout					: out std_logic_vector(31 downto 0)
	);
end TG68K_ALU;

architecture logic of TG68K_ALU is
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
-- ALU and more - Internal signal declarations
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
	-- Primary operand and adder/subtractor signals
	signal OP1in				: std_logic_vector(31 downto 0);  -- Processed operand 1
	signal addsub_a			: std_logic_vector(31 downto 0);  -- Adder input A
	signal addsub_b			: std_logic_vector(31 downto 0);  -- Adder input B
	signal notaddsub_b		: std_logic_vector(33 downto 0);  -- Inverted B for subtraction
	signal add_result			: std_logic_vector(33 downto 0);  -- Extended result for carry
	signal addsub_ofl			: std_logic_vector(2 downto 0);   -- Overflow flags (byte/word/long)
	signal opaddsub			: bit;                             -- Operation: 0=add, 1=sub
	signal c_in					: std_logic_vector(3 downto 0);   -- Carry chain
	signal flag_z				: std_logic_vector(2 downto 0);   -- Zero flags (byte/word/long)
	signal set_Flags			: std_logic_vector(3 downto 0);	-- NZVC flags to set
	signal CCRin				: std_logic_vector(7 downto 0);   -- New CCR value
	signal last_Flags1		: std_logic_vector(3 downto 0);	-- Previous NZVC flags
    
-- BCD arithmetic signals
	signal bcd_pur				: std_logic_vector(9 downto 0);   -- Pure binary result
	signal bcd_kor				: std_logic_vector(8 downto 0);   -- BCD correction value
	signal halve_carry		: std_logic;                      -- Half-carry for BCD
	signal Vflag_a				: std_logic;                      -- BCD V flag
	signal bcd_a_carry		: std_logic;                      -- BCD carry out
	signal bcd_a				: std_logic_vector(8 downto 0);   -- BCD adjusted result
	
	-- Multiplication signals
	signal result_mulu		: std_logic_vector(127 downto 0); -- Extended multiply result
	signal result_div			: std_logic_vector(63 downto 0);  -- Division result
	signal result_div_pre	: std_logic_vector(31 downto 0);  -- Pre-negated quotient
	signal set_mV_Flag		: std_logic;                      -- Multiply overflow
	signal V_Flag				: bit;                             -- Division overflow
	
	-- Rotation/shift signals
	signal rot_rot				: std_logic;                      -- MSB for rotation
	signal rot_lsb				: std_logic;                      -- LSB input for rotation
	signal rot_msb				: std_logic;                      -- MSB input for rotation
	signal rot_X				: std_logic;                      -- X flag output
	signal rot_C				: std_logic;                      -- C flag output
	signal rot_out				: std_logic_vector(31 downto 0);  -- Rotation result
	signal asl_VFlag			: std_logic;                      -- ASL overflow accumulator
	
	-- Bit operation signals
	signal bit_bits			: std_logic_vector(1 downto 0);
	signal bit_number			: std_logic_vector(4 downto 0);   -- Bit position
	signal bits_out			: std_logic_vector(31 downto 0);  -- Bit operation result
	signal one_bit_in			: std_logic;                      -- Selected bit value
	signal bchg					: std_logic;                      -- Bit change flag
	signal bset					: std_logic;                      -- Bit set flag
	
	-- Multiplication hardware signals
	signal mulu_sign			: std_logic;
	signal mulu_signext		: std_logic_vector(16 downto 0);
	signal muls_msb			: std_logic;
	signal mulu_reg			: std_logic_vector(63 downto 0);  -- Multiply accumulator
	signal FAsign				: std_logic;                      -- Factor A sign
	signal faktorA				: std_logic_vector(31 downto 0);  -- Multiply factor A
	signal faktorB				: std_logic_vector(31 downto 0);  -- Multiply factor B
	
	-- Division hardware signals
	signal div_reg				: std_logic_vector(63 downto 0);  -- Division working register
	signal div_quot			: std_logic_vector(63 downto 0);  -- Quotient accumulator
	signal div_ovl				: std_logic;
	signal div_neg				: std_logic;                      -- Negate quotient flag
	signal div_bit				: std_logic;                      -- Division bit result
	signal div_sub				: std_logic_vector(32 downto 0);  -- Division subtraction
	signal div_over			: std_logic_vector(32 downto 0);  -- Overflow detection
	signal nozero				: std_logic;                      -- Non-zero quotient
	signal div_qsign			: std_logic;                      -- Quotient sign
	signal dividend			: std_logic_vector(63 downto 0);  -- Extended dividend
	signal divs					: std_logic;                      -- Signed division
	signal signedOP			: std_logic;                      -- Signed operation
	signal OP1_sign			: std_logic;                      -- Operand 1 sign
	signal OP2_sign			: std_logic;                      -- Operand 2 sign
	signal OP2outext			: std_logic_vector(15 downto 0);  -- Sign extension

	-- Bit field signals
	signal in_offset			: std_logic_vector(5 downto 0);
	signal datareg				: std_logic_vector(31 downto 0);  -- Bit field data register
	signal insert				: std_logic_vector(31 downto 0);
	signal bf_datareg			: std_logic_vector(31 downto 0);  -- Bit field result
	signal result				: std_logic_vector(39 downto 0);  -- Extended bit field result
	signal result_tmp			: std_logic_vector(39 downto 0);
	signal unshifted_bitmask: std_logic_vector(31 downto 0);  -- Initial bit mask
	signal bf_set1				: std_logic_vector(39 downto 0);
	signal inmux0				: std_logic_vector(39 downto 0);  -- Shift mux stages
	signal inmux1				: std_logic_vector(39 downto 0);
	signal inmux2				: std_logic_vector(39 downto 0);
	signal inmux3				: std_logic_vector(31 downto 0);
	signal shifted_bitmask	: std_logic_vector(39 downto 0);  -- Final bit mask
	signal bitmaskmux0		: std_logic_vector(37 downto 0);  -- Mask shift stages
	signal bitmaskmux1		: std_logic_vector(35 downto 0);
	signal bitmaskmux2		: std_logic_vector(31 downto 0);
	signal bitmaskmux3		: std_logic_vector(31 downto 0);
	signal bf_set2				: std_logic_vector(31 downto 0);
	signal shift				: std_logic_vector(39 downto 0);
	signal bf_firstbit		: std_logic_vector(5 downto 0);   -- BFFFO result
	signal mux					: std_logic_vector(3 downto 0);
	signal bitnr				: std_logic_vector(4 downto 0);
	signal mask					: std_logic_vector(31 downto 0);
	signal mask_not_zero		: std_logic;
	signal bf_bset				: std_logic;                      -- Bit field set
	signal bf_NFlag			: std_logic;                      -- Bit field N flag
	signal bf_bchg				: std_logic;                      -- Bit field change
	signal bf_ins				: std_logic;                      -- Bit field insert
	signal bf_exts				: std_logic;                      -- Bit field extract signed
	signal bf_fffo				: std_logic;                      -- Bit field find first one
	signal bf_d32				: std_logic;                      -- 32-bit data register
	signal bf_s32				: std_logic;                      -- 32-bit source
	signal index				: std_logic_vector(4 downto 0);

	-- Barrel shifter signals
	signal hot_msb				: std_logic_vector(33 downto 0);  -- One-hot MSB position
	signal vector				: std_logic_vector(32 downto 0);  -- Extended input vector
	signal result_bs			: std_logic_vector(65 downto 0);  -- Barrel shifter result
	signal bit_nr				: std_logic_vector(5 downto 0);   -- Shift count
	signal bit_msb				: std_logic_vector(5 downto 0);   -- MSB position
	signal bs_shift			: std_logic_vector(5 downto 0);   -- Barrel shift amount
	signal bs_shift_mod		: std_logic_vector(5 downto 0);   -- Modulo shift count
	signal asl_over			: std_logic_vector(32 downto 0);  -- ASL overflow detect
	signal asl_over_xor		: std_logic_vector(32 downto 0);  -- ASL XOR chain
	signal asr_sign			: std_logic_vector(32 downto 0);  -- ASR sign extension
	signal msb					: std_logic;                      -- Most significant bit
	signal ring					: std_logic_vector(5 downto 0);   -- Rotation ring size
	signal ALU					: std_logic_vector(31 downto 0);  -- ALU working register
	signal BSout				: std_logic_vector(31 downto 0);  -- Barrel shifter output
	signal bs_V					: std_logic;                      -- Barrel shifter V flag
	signal bs_C					: std_logic;                      -- Barrel shifter C flag
	signal bs_X					: std_logic;                      -- Barrel shifter X flag


BEGIN
-----------------------------------------------------------------------------
-- ALU Result Multiplexer - Selects final ALU output based on operation
-----------------------------------------------------------------------------
PROCESS (OP2out, reg_QB, opcode, OP1out, OP1in, exe_datatype, addsub_q, execOPC, exec,
			bcd_a, result_mulu, result_div, exe_condition, bf_shift, bf_ffo_offset, mulu_reg, BSout,
			Flags, FlagsSR, bits_out, exec_tas, rot_out, exe_opcode, result, bf_fffo, bf_firstbit, bf_datareg)
	BEGIN
		-- Default output is OP1in
		ALUout <= OP1in;
		-- TAS instruction sets bit 7
		ALUout(7) <= OP1in(7) OR exec_tas;
		
		-- Bit field write-back operations
		IF exec(opcBFwb)='1' THEN
			ALUout <= result(31 downto 0);
			-- BFFFO (find first one) returns the bit position
			IF bf_fffo='1' THEN
				ALUout <= bf_ffo_offset - bf_firstbit;
			END IF;
		END IF;
		
		-- OP1in multiplexer - selects source for ALU result
		OP1in <= addsub_q;  -- Default: addition/subtraction result
		
		-- BCD arithmetic operations
		IF exec(opcABCD)='1' OR exec(opcSBCD)='1' THEN	
			OP1in(7 downto 0) <= bcd_a(7 downto 0);
			
		-- Multiplication operations
		ELSIF exec(opcMULU)='1' AND MUL_Mode/=3 THEN
			IF MUL_Hardware=0 THEN  -- Iterative multiplier
				IF exec(write_lowlong)='1' AND (MUL_Mode=1 OR MUL_Mode=2) THEN
					OP1in <= result_mulu(31 downto 0);	 -- Lower 32 bits
				ELSE	
					OP1in <= result_mulu(63 downto 32); -- Upper 32 bits
				END IF;		
			ELSE  -- Hardware multiplier
				IF exec(write_lowlong)='1' THEN
					OP1in <= result_mulu(31 downto 0);	
				ELSE	
					OP1in <= mulu_reg(31 downto 0);
				END IF;
			END IF;
			
		-- Division operations
		ELSIF exec(opcDIVU)='1' AND DIV_Mode/=3 THEN
			IF exe_opcode(15)='1' OR DIV_Mode=0 THEN
				-- 16-bit division: remainder in upper word, quotient in lower
				OP1in <= result_div(47 downto 32)&result_div(15 downto 0);	
			ELSE		
				-- 32-bit division
				IF exec(write_reminder)='1' THEN
					OP1in <= result_div(63 downto 32);  -- Remainder
				ELSE	
					OP1in <= result_div(31 downto 0);   -- Quotient
				END IF;
			END IF;
			
		-- Logical operations
		ELSIF exec(opcOR)='1' THEN
			OP1in <= OP2out OR OP1out;
		ELSIF exec(opcAND)='1' THEN
			OP1in <= OP2out AND OP1out;
		ELSIF exec(opcScc)='1' THEN
			-- Set according to condition
			OP1in(7 downto 0) <= (others=>exe_condition); 
		ELSIF exec(opcEOR)='1' THEN
			OP1in <= OP2out XOR OP1out;
		ELSIF exec(alu_move)='1' THEN
			OP1in <= OP2out;
			
		-- Rotation operations
		ELSIF exec(opcROT)='1' THEN
			OP1in <= rot_out;
			
		-- Barrel shifter operations
		ELSIF exec(exec_BS)='1' THEN
			OP1in <= BSout;
			
		-- SWAP operation (exchange upper/lower words)
		ELSIF exec(opcSWAP)='1' THEN	
			OP1in <= OP1out(15 downto 0)& OP1out(31 downto 16);
			
		-- Bit operations (BTST, BCHG, BCLR, BSET)
		ELSIF exec(opcBITS)='1' THEN
			OP1in <= bits_out;	
			
		-- Bit field operations
		ELSIF exec(opcBF)='1' THEN
			OP1in <= bf_datareg;
			
		-- Move from SR/CCR
		ELSIF exec(opcMOVESR)='1' THEN
			OP1in(7 downto 0) <= Flags;
			IF exe_opcode(9)='1' THEN
				OP1in(15 downto 8) <= "00000000";  -- CCR only
			ELSE	
				OP1in(15 downto 8) <= FlagsSR;     -- Full SR
			END IF;
			
		-- PACK operation (BCD pack)
		ELSIF exec(opcPACK)='1' THEN	
			OP1in(7 downto 0) <= addsub_q(11 downto 8) & addsub_q(3 downto 0);
		END IF;
	END PROCESS;
	
-----------------------------------------------------------------------------
-- Addition/Subtraction Unit
-- Handles all arithmetic operations including address calculations
-----------------------------------------------------------------------------
PROCESS (OP1out, OP2out, execOPC, Flags, long_start, movem_presub, exe_datatype, exec, addsub_a, addsub_b, opaddsub,
	     notaddsub_b, add_result, c_in, sndOPC, non_aligned, check_aligned)
	BEGIN
		-- Select adder input A
		addsub_a <= OP1out;
		IF exec(get_bfoffset)='1' THEN	
			-- Bit field offset calculation
			IF sndOPC(11)='1' THEN
				-- Sign-extended data register offset
				addsub_a <= OP1out(31)&OP1out(31)&OP1out(31)&OP1out(31 downto 3);
			ELSE
				-- Immediate offset
				addsub_a <= "000000000000000000000000000000"&sndOPC(10 downto 9);
			END IF;	
		END IF;
		
		-- Determine operation (add or subtract)
		IF exec(subidx)='1' THEN
			opaddsub <= '1';  -- Subtract
		ELSE
			opaddsub <= '0';  -- Add
		END IF;
		
		-- Select adder input B and carry in
		c_in(0) <='0';
		addsub_b <= OP2out;
		
		-- Special cases for B input
		IF exec(opcUNPACK)='1' THEN
			-- UNPK: expand nibbles to bytes
			addsub_b(15 downto 0) <= "0000" & OP2out(7 downto 4) & "0000" & OP2out(3 downto 0);
		ELSIF execOPC='0' AND exec(OP2out_one)='0' AND exec(get_bfoffset)='0'THEN
			-- Address calculation increments based on data size
			IF long_start='0' AND exe_datatype="00" AND exec(use_SP)='0' THEN
				addsub_b <= "00000000000000000000000000000001";  -- Byte: +1
			ELSIF long_start='0' AND exe_datatype="10" AND (exec(presub) OR exec(postadd) OR movem_presub)='1' THEN
				IF exec(movem_action)='1' THEN
					addsub_b <= "00000000000000000000000000000110";  -- MOVEM long: +6
				ELSE
					addsub_b <= "00000000000000000000000000000100";  -- Long: +4
				END IF;
			ELSE 
				addsub_b <= "00000000000000000000000000000010";  -- Word: +2
			END IF;
		ELSE	
			-- Extended operations use X flag as carry in
			IF (exec(use_XZFlag)='1' AND Flags(4)='1') OR exec(opcCHK)='1' THEN 
				c_in(0) <= '1';
			END IF;
			opaddsub <= exec(addsub);
		END IF;

		-- Special handling for unaligned MOVEM operations
		if exec(movem_action)='1' OR check_aligned='1' then
		  if (movem_presub = '0') then -- Post-increment
			if (non_aligned = '1') and (long_start = '0') then -- Hold address
			  addsub_b <= (others => '0');
			end if;
		  else  -- Pre-decrement
			if (non_aligned = '1') and (long_start = '0') then
			  if (exe_datatype = "10") then
				addsub_b <= "00000000000000000000000000001000";  -- -8 for unaligned long
			  else
				addsub_b <= "00000000000000000000000000000100";  -- -4 for unaligned word
			  end if;
			end if;
		  end if;
		end if;

		-- Prepare B input for addition/subtraction
		IF opaddsub='0' OR long_start='1' THEN		--ADD
			notaddsub_b <= '0'&addsub_b&c_in(0);
		ELSE					--SUB (one's complement + 1)
			notaddsub_b <= NOT ('0'&addsub_b&c_in(0));
		END IF;
		
		-- Perform addition with carry propagation
		add_result <= (('0'&addsub_a&notaddsub_b(0))+notaddsub_b);
		
		-- Calculate carry bits for each data size
		c_in(1) <= add_result(9) XOR addsub_a(8) XOR addsub_b(8);    -- Byte carry
		c_in(2) <= add_result(17) XOR addsub_a(16) XOR addsub_b(16); -- Word carry
		c_in(3) <= add_result(33);                                    -- Long carry
		
		-- Extract result
		addsub_q <= add_result(32 downto 1); 
		
		-- Calculate overflow flags for each data size
		addsub_ofl(0) <= (c_in(1) XOR add_result(8) XOR addsub_a(7) XOR addsub_b(7));		--V Byte
		addsub_ofl(1) <= (c_in(2) XOR add_result(16) XOR addsub_a(15) XOR addsub_b(15));	--V Word
		addsub_ofl(2) <= (c_in(3) XOR add_result(32) XOR addsub_a(31) XOR addsub_b(31));	--V Long
		
		-- Output carry bits (shifted for flag positions)
		c_out <= c_in(3 downto 1);
	END PROCESS;
	
------------------------------------------------------------------------------
-- BCD Arithmetic Unit
-- Implements ABCD (Add BCD) and SBCD (Subtract BCD) with proper correction
------------------------------------------------------------------------------		
PROCESS (OP1out, OP2out, CPU, exec, add_result, bcd_pur, bcd_a, bcd_kor, halve_carry, c_in)
	BEGIN
--BCD_ARITH-------------------------------------------------------------------
--04.04.2017 by Tobiflex - BCD handling with all undefined behavior!
		-- Get pure binary result with carry
		bcd_pur <= c_in(1)&add_result(8 downto 0);
		bcd_kor <= "000000000";  -- Correction value
		
		-- Half-carry detection (bit 4 carry)
		halve_carry <= OP1out(4) XOR OP2out(4) XOR bcd_pur(5); 
		
		-- Initial correction for invalid BCD
		IF halve_carry='1' THEN
			bcd_kor(3 downto 0) <= "0110"; --  -6 correction
		END IF;
		IF bcd_pur(9)='1' THEN
			bcd_kor(7 downto 4) <= "0110"; --  -60 correction
		END IF;
		
		-- ABCD operation
		IF exec(opcABCD)='1' THEN	
			-- V flag: set if sign changes from negative to positive
			Vflag_a <= NOT bcd_pur(8) AND bcd_a(7); 
			-- Apply initial correction
			bcd_a <= bcd_pur(9 downto 1) + bcd_kor;
			-- Check if further correction needed for invalid BCD digits
			IF (bcd_pur(4) AND (bcd_pur(3) OR bcd_pur(2)))='1' THEN
				bcd_kor(3 downto 0) <= "0110"; --  +6
			END IF;
			IF (bcd_pur(8) AND (bcd_pur(7) OR bcd_pur(6) OR (bcd_pur(5) AND bcd_pur(4) AND (bcd_pur(3) OR bcd_pur(2)))))='1' THEN
				bcd_kor(7 downto 4) <= "0110"; --  +60 
			END IF;
		ELSE -- SBCD operation
			-- V flag: set if sign changes from positive to negative
			Vflag_a <= bcd_pur(8) AND NOT bcd_a(7); 
			-- Apply subtraction correction
			bcd_a <= bcd_pur(9 downto 1) - bcd_kor;
		END IF;
		
		-- 68020 always clears V flag for BCD operations
		IF cpu(1)='1' THEN
			Vflag_a <= '0'; --68020
		END IF;
		
		-- BCD carry output
		bcd_a_carry <= bcd_pur(9) OR bcd_a(8);
	END PROCESS;
			
-----------------------------------------------------------------------------
-- Bit Operations Unit (BTST, BCHG, BCLR, BSET)
-----------------------------------------------------------------------------
PROCESS (clk, exe_opcode, OP1out, OP2out, reg_QB, one_bit_in, bchg, bset, bit_Number, sndOPC)
	BEGIN
		IF rising_edge(clk) THEN		
	        IF  clkena_lw = '1' THEN
				-- Decode bit operation from opcode
				bchg <= '0';
				bset <= '0';
				CASE opcode(7 downto 6) IS
					WHEN "01" =>					--bchg (bit change)
						bchg <= '1';
					WHEN "11" =>					--bset (bit set)
						bset <= '1';
					WHEN OTHERS => NULL;			-- 00=btst, 10=bclr
				END CASE;
			END IF;
		END IF;		
		
		-- Select bit number from immediate or register
		IF exe_opcode(8)='0' THEN  -- Immediate bit number
			IF exe_opcode(5 downto 4)="00" THEN
				bit_number <= sndOPC(4 downto 0);         -- Long: 32 bits
			ELSE
				bit_number <= "00"&sndOPC(2 downto 0);    -- Byte: 8 bits
			END IF;
		ELSE  -- Dynamic bit number from register
			IF exe_opcode(5 downto 4)="00" THEN
				bit_number <= reg_QB(4 downto 0);         -- Long: 32 bits
			ELSE
				bit_number <= "00"&reg_QB(2 downto 0);    -- Byte: 8 bits
			END IF;
		END IF;
						
		-- Extract bit value and perform operation
		one_bit_in <= OP1out(conv_integer(bit_Number));
		bits_out <= OP1out;
		-- Modify bit: BCHG toggles, BSET sets to 1, BCLR clears to 0
		bits_out(conv_integer(bit_Number)) <= (bchg AND NOT one_bit_in) OR bset ;
	END PROCESS;

-----------------------------------------------------------------------------
-- Bit Field Unit
-- Implements 68020 bit field instructions (BFTST, BFEXTU, BFCHG, etc.)
-----------------------------------------------------------------------------	

PROCESS (clk, mux, mask, bitnr, bf_ins, bf_bchg, bf_bset, bf_exts, bf_shift, inmux0, inmux1, inmux2, inmux3, bf_set2, OP1out, OP2out, 
			result_tmp, bf_ext_in, mask_not_zero, exec, shift, datareg, bf_NFlag, result, reg_QB, unshifted_bitmask, bf_d32, bf_s32, 
			shifted_bitmask, bf_loffset, bitmaskmux0, bitmaskmux1, bitmaskmux2, bitmaskmux3, bf_width)
	BEGIN
		IF rising_edge(clk) THEN		
			IF clkena_lw = '1' THEN
				-- Initialize bit field operation flags
				bf_bset <= '0';
				bf_bchg <= '0';
				bf_ins <= '0';
				bf_exts <= '0';
				bf_fffo <= '0';
				bf_d32 <= '0';
				bf_s32 <= '0';
				
				-- Decode bit field operation
--		000-bftst, 001-bfextu, 010-bfchg, 011-bfexts, 100-bfclr, 101-bfff0, 110-bfset, 111-bfins	
				IF opcode(5 downto 4) ="00" THEN
					  bf_s32 <= '1';  -- 32-bit source
				END IF;
				CASE opcode(10 downto 8) IS
					WHEN "010" => bf_bchg <= '1';					--BFCHG (change)
					WHEN "011" => bf_exts <= '1';					--BFEXTS (extract signed)
					WHEN "101" => bf_fffo <= '1';					--BFFFO (find first one)
					WHEN "110" => bf_bset <= '1';					--BFSET (set)
					WHEN "111" => bf_ins <= '1';					--BFINS (insert)
									  bf_s32 <= '1';
					WHEN OTHERS => NULL;
				END CASE;
				IF opcode(4 downto 3)="00" THEN
					bf_d32 <= '1';  -- 32-bit destination
				END IF;
				-- Store extension bits for memory operations
				bf_ext_out <= result(39 downto 32);
			END IF;
		END IF;
		
		-- Select data source (insert uses different register)
		IF bf_ins='1' THEN
			datareg <= reg_QB;
		ELSE
			datareg <= bf_set2;
		END IF;
		
		
-- Create bitmask for bit field operations
-- unshifted bitmask: '0' => bit is in the bit field
--                    '1' => bit is not in the bit field
-- Example: bf_width=11 => "11111111 11111111 11111000 00000000"
		unshifted_bitmask <= (OTHERS => '0'); 
		FOR i in 0 to 31 LOOP
			IF i>bf_width(4 downto 0) THEN
				datareg(i) <= '0';              -- Clear bits outside field
				unshifted_bitmask(i) <= '1';    -- Mark as outside field
			END IF;	
		END LOOP;
		
		-- Get N flag from most significant bit of field
		bf_NFlag <= datareg(conv_integer(bf_width));
		
		-- Sign extend for BFEXTS
		IF bf_exts='1' AND bf_NFlag='1' THEN
			bf_datareg <= datareg OR unshifted_bitmask;
		ELSE	
			bf_datareg <= datareg;
		END IF;	
		
-- Shift bitmask to correct position
-- Multi-stage barrel shifter for mask positioning
		-- Stage 4: Shift by 16
		IF bf_loffset(4)='1' THEN 
			bitmaskmux3 <= unshifted_bitmask(15 downto 0)&unshifted_bitmask(31 downto 16);
		ELSE	
			bitmaskmux3 <= unshifted_bitmask;
		END IF;
		-- Stage 3: Shift by 8
		IF bf_loffset(3)='1' THEN 
			bitmaskmux2(31 downto 0) <= bitmaskmux3(23 downto 0)&bitmaskmux3(31 downto 24);
		ELSE	
			bitmaskmux2(31 downto 0) <= bitmaskmux3;
		END IF;
		-- Stage 2: Shift by 4
		IF bf_loffset(2)='1' THEN 
			bitmaskmux1 <= bitmaskmux2&"1111";
			IF bf_d32='1' THEN  -- Wrap around for 32-bit destination
				bitmaskmux1(3 downto 0) <= bitmaskmux2(31 downto 28);
			END IF;
		ELSE	
			bitmaskmux1 <= "1111"&bitmaskmux2;
		END IF;
		-- Stage 1: Shift by 2
		IF bf_loffset(1)='1' THEN 
			bitmaskmux0 <= bitmaskmux1&"11";
			IF bf_d32='1' THEN 
				bitmaskmux0(1 downto 0) <= bitmaskmux1(31 downto 30);
			END IF;
		ELSE
			bitmaskmux0 <= "11"&bitmaskmux1;
		END IF;
		-- Stage 0: Shift by 1
		IF bf_loffset(0)='1' THEN 
			shifted_bitmask <= '1'&bitmaskmux0&'1';
			IF bf_d32='1' THEN 
				shifted_bitmask(0) <= bitmaskmux0(31);
			END IF;
		ELSE
			shifted_bitmask <= "11"&bitmaskmux0;
		END IF;
		
		
-- Shift data for insert operation
		shift <= bf_ext_in&OP2out;  -- Combine extension and operand
		IF bf_s32='1' THEN 
			shift(39 downto 32) <= OP2out(7 downto 0);  -- Wrap for 32-bit
		END IF;
		
		-- Multi-stage barrel shifter for data
		IF bf_shift(0)='1' THEN 
			inmux0 <= shift(0)&shift(39 downto 1);
		ELSE	
			inmux0 <= shift;
		END IF;
		IF bf_shift(1)='1' THEN 
			inmux1 <= inmux0(1 downto 0)&inmux0(39 downto 2);
		ELSE
			inmux1 <= inmux0;
		END IF;
		IF bf_shift(2)='1' THEN 
			inmux2 <= inmux1(3 downto 0)&inmux1(39 downto 4);
		ELSE	
			inmux2 <= inmux1;
		END IF;
		IF bf_shift(3)='1' THEN 
			inmux3 <= inmux2(7 downto 0)&inmux2(31 downto 8);
		ELSE	
			inmux3 <= inmux2(31 downto 0);
		END IF;
		IF bf_shift(4)='1' THEN 
			bf_set2(31 downto 0) <= inmux3(15 downto 0)&inmux3(31 downto 16);
		ELSE	
			bf_set2(31 downto 0) <= inmux3;
		END IF;
		
		-- Prepare operation result
		IF bf_ins='1' THEN
			result(31 downto 0) <= bf_set2;
			result(39 downto 32) <= bf_set2(7 downto 0);
		ELSIF bf_bchg='1' THEN
			result(31 downto 0) <= NOT OP2out;           -- Invert for BFCHG
			result(39 downto 32) <= NOT bf_ext_in;
		ELSE	
			result <= (OTHERS => '0');                   -- Clear for BFCLR
		END IF;
		IF bf_bset='1' THEN
			result <= (OTHERS => '1');                   -- Set for BFSET
		END IF;
		
		-- Merge with original data using mask
		IF bf_ins='1' THEN
			result_tmp <= bf_ext_in&OP1out;              -- Use destination for insert
		ELSE	
			result_tmp <= bf_ext_in&OP2out;              -- Use source for others
		END IF;
		FOR i in 0 to 39 LOOP
			IF shifted_bitmask(i)='1' THEN	
				result(i) <= result_tmp(i);               -- Restore bits outside field
			END IF;	
		END LOOP;
		
--BFFFO (Find First One in Bit Field)
		mask <= datareg;
		bf_firstbit <= ('0'&bitnr)+mask_not_zero;
		bitnr <= "11111";  -- Start from bit 31
		mask_not_zero <= '1'; 
		
		-- Priority encoder to find first set bit
		IF mask(31 downto 28)="0000" THEN
			IF mask(27 downto 24)="0000" THEN
				IF mask(23 downto 20)="0000" THEN
					IF mask(19 downto 16)="0000" THEN
						bitnr(4) <= '0';  -- Bit is in lower 16
						IF mask(15 downto 12)="0000" THEN
							IF mask(11 downto 8)="0000" THEN
								bitnr(3) <= '0';  -- Bit is in lower 8
								IF mask(7 downto 4)="0000" THEN
									bitnr(2) <= '0';  -- Bit is in lower 4
									mux <= mask(3 downto 0);
								ELSE
									mux <= mask(7 downto 4);
								END IF;
							ELSE
								mux <= mask(11 downto 8);
								bitnr(2) <= '0';
							END IF;
						ELSE
							mux <= mask(15 downto 12);
						END IF;
					ELSE
						mux <= mask(19 downto 16);
						bitnr(3) <= '0';
						bitnr(2) <= '0';
					END IF;
				ELSE
					mux <= mask(23 downto 20);
					bitnr(3) <= '0';
				END IF;
			ELSE
				mux <= mask(27 downto 24);
				bitnr(2) <= '0';
			END IF;
		ELSE
			mux <= mask(31 downto 28);
		END IF;
		
		-- Final 4-to-2 priority encoder
		IF mux(3 downto 2)="00" THEN
			bitnr(1) <= '0';
			IF mux(1)='0' THEN
				bitnr(0) <= '0';
				IF mux(0)='0' THEN
					mask_not_zero <= '0';  -- No bit set
				END IF;	
			END IF;	
		ELSE		
			IF mux(3)='0' THEN
				bitnr(0) <= '0';
			END IF;	
		END  IF;
	END PROCESS;

-----------------------------------------------------------------------------
-- Rotation Unit
-- Handles ROL, ROR, ROXL, ROXR, ASL, ASR, LSL, LSR
-----------------------------------------------------------------------------
PROCESS (exe_opcode, OP1out, Flags, rot_bits, rot_msb, rot_lsb, rot_rot, exec, BSout)
	BEGIN
		-- Select MSB based on data size
		CASE exe_opcode(7 downto 6) IS
			WHEN "00" =>					--Byte
						rot_rot <= OP1out(7);
			WHEN "01"|"11" =>				--Word
						rot_rot <= OP1out(15);
			WHEN "10" =>					--Long
						rot_rot <= OP1out(31);
			WHEN OTHERS => NULL;
		END CASE;
	
		-- Select rotation fill bits based on operation type
		CASE rot_bits IS
			WHEN "00" =>					--ASL, ASR (arithmetic shift)
						rot_lsb <= '0';
						rot_msb <= rot_rot;     -- Sign extend for ASR
			WHEN "01" =>					--LSL, LSR (logical shift)
						rot_lsb <= '0';
						rot_msb <= '0';
			WHEN "10" =>					--ROXL, ROXR (rotate through X)
						rot_lsb <= Flags(4);    -- X flag
						rot_msb <= Flags(4);
			WHEN "11" =>					--ROL, ROR (rotate)
						rot_lsb <= rot_rot;     -- Wrap around
						rot_msb <= OP1out(0);
			WHEN OTHERS => NULL;
		END CASE;
	
		-- Handle no-operation case (shift count = 0)
		IF exec(rot_nop)='1' THEN
			rot_out <= OP1out;
			rot_X <= Flags(4);
			IF rot_bits="10" THEN	--ROXL, ROXR
				rot_C <= Flags(4);
			ELSE	
				rot_C <= '0';
			END IF;
		ELSE
			-- Perform rotation
			IF exe_opcode(8)='1' THEN		--left rotate/shift
				rot_out <= OP1out(30 downto 0)&rot_lsb;
				rot_X <= rot_rot;  -- Bit shifted out
				rot_C <= rot_rot;
			ELSE						--right rotate/shift
				rot_X <= OP1out(0);
				rot_C <= OP1out(0);
				rot_out <= rot_msb&OP1out(31 downto 1);
				-- Adjust MSB position for byte/word operations
				CASE exe_opcode(7 downto 6) IS
					WHEN "00" =>					--Byte
						rot_out(7) <= rot_msb;
					WHEN "01"|"11" =>				--Word
						rot_out(15) <= rot_msb;
					WHEN OTHERS => NULL;	
				END CASE;
			END IF;
			-- Use barrel shifter if available
			IF BarrelShifter/=0 THEN
			   rot_out <= BSout;
			END IF;
		END IF;
	END PROCESS;
		
-----------------------------------------------------------------------------
-- Barrel Shifter Unit
-- High-performance parallel shifter for 68020+ processors
-----------------------------------------------------------------------------	
process (OP1out, OP2out, opcode, bit_nr, bit_msb, bs_shift, bs_shift_mod, ring, result_bs, exe_opcode, vector, 
         rot_bits, Flags, bs_C, msb, hot_msb, asl_over, asl_over_xor, ALU, asr_sign, exec)
	begin
		-- Determine rotation ring size based on operation and data size
		ring <= "100000";  -- Default: 32-bit
		IF rot_bits="10" THEN --ROX L/R (rotate through X)
			CASE exe_opcode(7 downto 6) IS
				WHEN "00" =>					--Byte
							ring <= "001001";   -- 9 bits (8 + X)
				WHEN "01"|"11" =>				--Word
							ring <= "010001";   -- 17 bits (16 + X)
				WHEN "10" =>					--Long
							ring <= "100001";   -- 33 bits (32 + X)
				WHEN OTHERS => NULL;
			END CASE;
		ELSE
			CASE exe_opcode(7 downto 6) IS
				WHEN "00" =>					--Byte
							ring <= "001000";   -- 8 bits
				WHEN "01"|"11" =>				--Word
							ring <= "010000";   -- 16 bits
				WHEN "10" =>					--Long
							ring <= "100000";   -- 32 bits
				WHEN OTHERS => NULL;
			END CASE;
		END IF;	
		
		-- Extract shift count
		IF exe_opcode(7 downto 6)="11" OR exec(exec_BS)='0' THEN
			bs_shift <="000001";  -- Memory shifts are always by 1
		ELSIF exe_opcode(5)='1' THEN
			bs_shift <= OP2out(5 downto 0);  -- Register shift count
		ELSE
			-- Immediate shift count (1-8, encoded as 0-7)
			bs_shift(2 downto 0) <= exe_opcode(11 downto 9);
			IF exe_opcode(11 downto 9)="000" THEN
				bs_shift(5 downto 3) <="001";  -- 0 encodes as 8
			ELSE
				bs_shift(5 downto 3) <="000";
			END IF;
		END IF;

-- Calculate V flag for ASL (overflow if sign bit changes)
		bit_msb <= "000000";
		hot_msb <= (OTHERS =>'0');
		hot_msb(conv_integer(bit_msb)) <= '1';  -- One-hot encoding
		IF bs_shift < ring THEN
			bit_msb <= ring-bs_shift;
		END IF;
		-- XOR chain to detect sign changes
		asl_over_xor <= (('0'&vector(30 downto 0)) XOR ('0'&vector(31 downto 1)))&msb;
		CASE exe_opcode(7 downto 6) IS
			WHEN "00" =>					--Byte
				asl_over_xor(8) <= '0';
			WHEN "01"|"11" =>				--Word
				asl_over_xor(16) <= '0';
			WHEN OTHERS => NULL;
		END CASE;
		asl_over <= asl_over_xor - ('0'&hot_msb(31 downto 0));	
		bs_V <= '0';
		IF rot_bits="00" AND exe_opcode(8)='1' THEN --ASL
			bs_V <= not asl_over(32);  -- Overflow if any sign bit changed
		END IF;
		
		-- Set flags
		bs_X <= bs_C;
		IF exe_opcode(8)='0' THEN --right shift
			bs_C <= result_bs(31);  -- Last bit shifted out
		ELSE                  --left shift
			CASE exe_opcode(7 downto 6) IS
				WHEN "00" =>					--Byte
					bs_C <= result_bs(8);
				WHEN "01"|"11" =>				--Word
					bs_C <= result_bs(16);
				WHEN "10" =>					--Long
					bs_C <= result_bs(32);
				WHEN OTHERS => NULL;
			END CASE;
		END IF;
		
		-- Process rotation results
		ALU <= (others=>'-');
		IF rot_bits="11" THEN --RO L/R (rotate without X)
			bs_X <= Flags(4);  -- X unchanged
			CASE exe_opcode(7 downto 6) IS
				WHEN "00" =>					--Byte
					ALU(7 downto 0) <= result_bs(7 downto 0) OR result_bs(15 downto 8);
					bs_C <= ALU(7);
				WHEN "01"|"11" =>				--Word
					ALU(15 downto 0) <= result_bs(15 downto 0) OR result_bs(31 downto 16);
					bs_C <= ALU(15);
				WHEN "10" =>					--Long
					ALU <= result_bs(31 downto 0) OR result_bs(63 downto 32);
					bs_C <= ALU(31);
				WHEN OTHERS => NULL;
			END CASE;
			IF exe_opcode(8)='1' THEN --left shift
				bs_C <= ALU(0);  -- For left rotate, C gets LSB
			END IF;
		ELSIF rot_bits="10" THEN --ROX L/R (rotate through X)
			CASE exe_opcode(7 downto 6) IS
				WHEN "00" =>					--Byte
					ALU(7 downto 0) <= result_bs(7 downto 0) OR result_bs(16 downto 9);
					bs_C <= result_bs(8) OR result_bs(17);
				WHEN "01"|"11" =>				--Word
					ALU(15 downto 0) <= result_bs(15 downto 0) OR result_bs(32 downto 17);
					bs_C <= result_bs(16) OR result_bs(33);
				WHEN "10" =>					--Long
					ALU <= result_bs(31 downto 0) OR result_bs(64 downto 33);
					bs_C <= result_bs(32) OR result_bs(65);
				WHEN OTHERS => NULL;
			END CASE;
		ELSE  -- Shift operations
			IF exe_opcode(8)='0' THEN --right shift
				ALU <= result_bs(63 downto 32);
			ELSE                  --left shift
				ALU <= result_bs(31 downto 0);
			END IF;
		END IF;
		
		-- Handle zero shift count
		IF(bs_shift = "000000") THEN
			IF rot_bits="10" THEN --ROX L/R
				bs_C <= Flags(4);
			ELSE
				bs_C <= '0';
			END IF;
			bs_X <= Flags(4);
			bs_V <= '0';
		END IF;

-- Calculate modulo shift count for rotations
		-- Replace division with optimized logic for specific ring sizes
		CASE ring IS
			WHEN "001001" =>  -- 9-bit ring
				IF bs_shift = 63 THEN
					bs_shift_mod <= "000000";
				ELSIF bs_shift > 6*9-1 THEN
					bs_shift_mod <= bs_shift - 6*9;
				ELSIF bs_shift > 5*9-1 THEN
					bs_shift_mod <= bs_shift - 5*9;
				ELSIF bs_shift > 4*9-1 THEN
					bs_shift_mod <= bs_shift - 4*9;
				ELSIF bs_shift > 3*9-1 THEN
					bs_shift_mod <= bs_shift - 3*9;
				ELSIF bs_shift > 2*9-1 THEN
					bs_shift_mod <= bs_shift - 2*9;
				ELSIF bs_shift > 9-1 THEN
					bs_shift_mod <= bs_shift - 9;
				ELSE
					bs_shift_mod <= bs_shift;
				END IF;
			WHEN "010001" =>  -- 17-bit ring
				IF bs_shift > 3*17-1 THEN
					bs_shift_mod <= bs_shift - 3*17;
				ELSIF bs_shift > 2*17-1 THEN
					bs_shift_mod <= bs_shift - 2*17;
				ELSIF bs_shift > 17-1 THEN
					bs_shift_mod <= bs_shift - 17;
				ELSE
					bs_shift_mod <= bs_shift;
				END IF;
			WHEN "100001" =>  -- 33-bit ring
				IF bs_shift > 32 THEN
					bs_shift_mod <= bs_shift - 33;
				ELSE
					bs_shift_mod <= bs_shift;
				END IF;
			-- Power-of-2 rings use simple masking
			WHEN "001000" => bs_shift_mod <= "000" & bs_shift(2 downto 0);  -- 8-bit
			WHEN "010000" => bs_shift_mod <=  "00" & bs_shift(3 downto 0);  -- 16-bit
			WHEN "100000" => bs_shift_mod <=   "0" & bs_shift(4 downto 0);  -- 32-bit
			WHEN OTHERS => bs_shift_mod <= (OTHERS => '0');
		END CASE;

		-- Calculate actual shift position
		bit_nr <= bs_shift_mod(5 downto 0);
		IF exe_opcode(8)='0' THEN  --right shift
			bit_nr <= ring-bs_shift_mod;
		END IF;
		
		-- Special handling for shifts (not rotations)
		IF rot_bits(1)='0' THEN --only shift
			IF exe_opcode(8)='0' THEN  --right shift
				bit_nr <= 32-bs_shift_mod;
			END IF;
			-- Handle shift counts equal to data size
			IF bs_shift = ring THEN
				IF exe_opcode(8)='0' THEN  --right shift
					bit_nr <= 32-ring;
				ELSE	
					bit_nr <= ring;
				END IF;
			END IF;
			-- Handle shift counts greater than data size
			IF bs_shift > ring THEN
				IF exe_opcode(8)='0' THEN  --right shift
					bit_nr <= "000000";
					bs_C <= '0';
				ELSE	
					bit_nr <= ring+1;  -- Shift everything out
				END IF;
			END IF;
		END IF;
		
-- Handle ASR (arithmetic shift right) sign extension
		BSout <= ALU;
		asr_sign <= (OTHERS =>'0');	
		asr_sign(32 downto 1) <= asr_sign(31 downto 0) OR hot_msb(31 downto 0);	
		IF rot_bits="00" AND exe_opcode(8)='0' AND msb='1' THEN --ASR with negative
			BSout <= ALU or asr_sign(32 downto 1);  -- Fill with sign bit
			IF bs_shift > ring THEN
				bs_C <= '1';  -- Sign bit shifted out
			END IF;
		END IF;

		-- Prepare input vector with appropriate size
		vector(32 downto 0) <= '0'&OP1out;
		CASE exe_opcode(7 downto 6) IS
			WHEN "00" =>					--Byte
				msb <= OP1out(7);
				vector(31 downto 8) <= X"000000";
				BSout(31 downto 8) <= X"000000";
				IF rot_bits="10" THEN --ROX L/R
					vector(8) <= Flags(4);  -- Insert X flag
				END IF;
			WHEN "01"|"11" =>				--Word
				msb <= OP1out(15);
				vector(31 downto 16) <= X"0000";
				BSout(31 downto 16) <= X"0000";
				IF rot_bits="10" THEN --ROX L/R
					vector(16) <= Flags(4);
				END IF;
			WHEN "10" =>					--Long
				msb <= OP1out(31);
				IF rot_bits="10" THEN --ROX L/R
					vector(32) <= Flags(4);
				END IF;
			WHEN OTHERS => NULL;
		END CASE;
		
		-- Perform barrel shift
		result_bs <= std_logic_vector(unsigned('0'&X"00000000"&vector) sll to_integer(unsigned(bit_nr(5 downto 0)))); 

  end process;

  
------------------------------------------------------------------------------
-- Condition Code Register (CCR) and Flag Generation
------------------------------------------------------------------------------		
PROCESS (clk, Reset, exe_opcode, exe_datatype, Flags, last_data_read, OP2out, flag_z, OP1IN, c_out, addsub_ofl,
	     bcd_a, bcd_a_carry, Vflag_a, exec)
	BEGIN
		-- CCR logical operations (ANDI, EORI, ORI to CCR)
		IF exec(andiSR)='1' THEN
			CCRin <= Flags AND last_data_read(7 downto 0);
		ELSIF exec(eoriSR)='1' THEN
			CCRin <= Flags XOR last_data_read(7 downto 0);
		ELSIF exec(oriSR)='1' THEN
			CCRin <= Flags OR last_data_read(7 downto 0);
		ELSE	
			CCRin <= OP2out(7 downto 0);
		END IF;	
		
------------------------------------------------------------------------------
-- Zero Flag Calculation
-- Handles byte/word/long and extended precision operations
------------------------------------------------------------------------------		
		flag_z <= "000";
		-- Extended operations: Z is cleared only if result is non-zero
		IF exec(use_XZFlag)='1' AND flags(2)='0' THEN
			flag_z <= "000";
		ELSIF OP1in(7 downto 0)="00000000" THEN
			flag_z(0) <= '1';  -- Byte zero
			IF OP1in(15 downto 8)="00000000" THEN
				flag_z(1) <= '1';  -- Word zero
				IF OP1in(31 downto 16)="0000000000000000" THEN
					flag_z(2) <= '1';  -- Long zero
				END IF;
			END IF;
		END IF;
		
-- Set flags based on data size
		--Flags NZVC
		IF exe_datatype="00" THEN 						--Byte
			set_flags <= OP1IN(7)&flag_z(0)&addsub_ofl(0)&c_out(0);
			IF exec(opcABCD)='1' OR exec(opcSBCD)='1' THEN	
				set_flags(0) <= bcd_a_carry;     -- BCD carry
				set_flags(1) <= Vflag_a;         -- BCD overflow
			END IF;
		ELSIF exe_datatype="10" OR exec(opcCPMAW)='1' THEN 						--Long
			set_flags <= OP1IN(31)&flag_z(2)&addsub_ofl(2)&c_out(2);
		ELSE 						--Word
			set_flags <= OP1IN(15)&flag_z(1)&addsub_ofl(1)&c_out(1);
		END IF;
		
		-- Flag register update logic
		IF rising_edge(clk) THEN		
			IF Reset='1' THEN
				Flags(7 downto 0) <= "00000000"; 
			ELSIF clkena_lw = '1' THEN
				-- Direct flag loads (MOVE to SR/CCR, STOP)
				IF exec(directSR)='1' OR set_stop='1' THEN
					Flags(7 downto 0) <= data_read(7 downto 0);
				END IF;	
				IF exec(directCCR)='1' THEN
					Flags(7 downto 0) <= data_read(7 downto 0);
				END IF;	
				
				-- ASL V flag accumulator (set if any sign change occurs)
				IF exec(opcROT)='1' AND decodeOPC='0' THEN
					asl_VFlag <= ((set_flags(3) XOR rot_rot) OR asl_VFlag);	
				ELSE	
					asl_VFlag <= '0';
				END IF;	
				
				-- Update flags based on operation
				IF exec(to_CCR)='1' THEN
					Flags(7 downto 0) <= CCRin(7 downto 0);			--CCR
				ELSIF Z_error='1' THEN
					-- Division by zero: undocumented flag behavior
					IF micro_state = trap0 THEN
						IF exe_opcode(8)='0' THEN
							Flags(3 downto 0) <= '0'&NOT reg_QA(31)&"00";
						ELSE
							Flags(3 downto 0) <= "0100";
						END IF;
					END IF;
				ELSIF exec(no_Flags)='0' THEN
					last_Flags1 <= Flags(3 downto 0);  -- Save for CHK2
					
					-- X flag updates
					IF exec(opcADD)='1' THEN
						Flags(4) <= set_flags(0);  -- X = C for arithmetic
					ELSIF exec(opcROT)='1' AND rot_bits/="11" AND exec(rot_nop)='0' THEN
						Flags(4) <= rot_X; 	
					ELSIF exec(exec_BS)='1' THEN
						Flags(4) <= BS_X; 	
					END IF;
					
					-- NZVC flag updates by operation type
					IF (exec(opcCMP) OR exec(alu_setFlags))='1' THEN
						Flags(3 downto 0) <= set_flags;
					ELSIF exec(opcDIVU)='1' AND DIV_Mode/=3 THEN
						-- Division flags
						IF V_Flag='1' THEN	
							Flags(3 downto 0) <= "1010";  -- N=1, Z=0, V=1, C=0
						ELSIF exe_opcode(15)='1' OR DIV_Mode=0 THEN
							Flags(3 downto 0) <= OP1IN(15)&flag_z(1)&"00";
						ELSE
							Flags(3 downto 0) <= OP1IN(31)&flag_z(2)&"00";
						END IF;
					ELSIF exec(write_reminder)='1' AND MUL_Mode/=3 THEN -- MULU.l upper result
						Flags(3) <= set_flags(3);
						Flags(2) <= set_flags(2) AND Flags(2);  -- Z only if both parts zero
						Flags(1) <= '0';
						Flags(0) <= '0';
					ELSIF exec(write_lowlong)='1' AND (MUL_Mode=1 OR MUL_Mode=2) THEN  -- MULU.l lower
						Flags(3) <= set_flags(3);
						Flags(2) <= set_flags(2);
						Flags(1) <= set_mV_Flag;	--V
						Flags(0) <= '0';
					ELSIF exec(opcOR)='1' OR exec(opcAND)='1' OR exec(opcEOR)='1' OR exec(opcMOVE)='1' OR exec(opcMOVEQ)='1' OR exec(opcSWAP)='1' OR exec(opcBF)='1' OR (exec(opcMULU)='1' AND MUL_Mode/=3) THEN
						-- Logical operations: only N and Z affected
						Flags(1 downto 0) <= "00";
						Flags(3 downto 2) <= set_flags(3 downto 2);
						IF exec(opcBF)='1' THEN
							Flags(3) <= bf_NFlag;  -- Bit field N flag
						END IF;	
					ELSIF exec(opcROT)='1' THEN
						-- Rotation flags
						Flags(3 downto 2) <= set_flags(3 downto 2);
						Flags(0) <= rot_C;
						IF rot_bits="00" AND ((set_flags(3) XOR rot_rot) OR asl_VFlag)='1' THEN		--ASL/ASR
							Flags(1) <= '1';  -- V set if sign changed
						ELSE		
							Flags(1) <= '0';
						END IF;	
					ELSIF exec(exec_BS)='1' THEN
						-- Barrel shifter flags
						Flags(3 downto 2) <= set_flags(3 downto 2);
						Flags(0) <= BS_C;
						Flags(1) <= BS_V;
					ELSIF exec(opcBITS)='1' THEN
						-- Bit test: only Z affected
						Flags(2) <= NOT one_bit_in;	
					ELSIF exec(opcCHK2)='1' THEN		
						-- CHK2 bounds check flags
						-- Lower bound first, then upper bound
						IF last_Flags1(0)='0' THEN			--unsigned
							Flags(0) <= Flags(0) OR (NOT set_flags(0) AND NOT set_flags(2));
						ELSE										--signed
							Flags(0) <= (Flags(0) XOR set_flags(0)) AND  NOT Flags(2) AND NOT set_flags(2);
						END IF;
						Flags(1) <= '0';
						Flags(2) <= Flags(2) OR set_flags(2);  -- Z if equal to bound
						Flags(3) <= NOT last_Flags1(0); 
					ELSIF exec(opcCHK)='1' THEN
						-- CHK exception check
						IF exe_datatype="01" THEN 						--Word
							Flags(3) <= OP1out(15);
						ELSE	
							Flags(3) <= OP1out(31);
						END IF;	
						IF OP1out(15 downto 0)=X"0000" AND (exe_datatype="01" OR OP1out(31 downto 16)=X"0000") THEN
							Flags(2) <='1';
						ELSE	
							Flags(2) <='0';
						END IF;	
						Flags(1) <= '0';
						Flags(0) <= '0';
					END IF;
				END IF;	
			END IF;	
			Flags(7 downto 5) <= "000";  -- Always clear upper SR bits in CCR
		END IF;	
	END PROCESS;
	
---------------------------------------------------------------------------------
-- Multiplication Unit
-- Supports both 16x16 and 32x32 operations
-- Two implementations: hardware multiplier or iterative
---------------------------------------------------------------------------------	
PROCESS (exe_opcode, OP2out, muls_msb, mulu_reg, FAsign, mulu_sign, reg_QA, faktorA, faktorB, result_mulu, signedOP)
	BEGIN
	IF MUL_Hardware=1 THEN
		-- Hardware multiplier implementation
		IF MUL_Mode=0 THEN	-- 16-bit only mode
			-- Sign extend factors for signed multiply
			IF signedOP='1' AND reg_QA(15)='1' THEN
				faktorA <= X"FFFFFFFF";
			ELSE	
				faktorA <= X"00000000";
			END IF;
			IF signedOP='1' AND OP2out(15)='1' THEN
				faktorB <= X"FFFFFFFF";
			ELSE	
				faktorB <= X"00000000";
			END IF;
			-- 16x16 multiply (using 32x32 multiplier)
			result_mulu(63 downto 0) <= (faktorA(15 downto 0) & reg_QA(15 downto 0)) * (faktorB(15 downto 0) & OP2out(15 downto 0));
		ELSE
			-- 16 or 32-bit selectable
			IF exe_opcode(15)='1' THEN	-- 16-bit operation
				IF signedOP='1' AND reg_QA(15)='1' THEN
					faktorA <= X"FFFFFFFF";
				ELSE	
					faktorA <= X"00000000";
				END IF;
				IF signedOP='1' AND OP2out(15)='1' THEN
					faktorB <= X"FFFFFFFF";
				ELSE	
					faktorB <= X"00000000";
				END IF;
			ELSE	-- 32-bit operation
				faktorA(15 downto 0) <= reg_QA(31 downto 16);
				faktorB(15 downto 0) <= OP2out(31 downto 16);
				IF signedOP='1' AND reg_QA(31)='1' THEN
					faktorA(31 downto 16) <= X"FFFF";
				ELSE	
					faktorA(31 downto 16) <= X"0000";
				END IF;
				IF signedOP='1' AND OP2out(31)='1' THEN
					faktorB(31 downto 16) <= X"FFFF";
				ELSE	
					faktorB(31 downto 16) <= X"0000";
				END IF;
			END IF;
			-- 32x32 multiply (produces 64-bit result, extended to 128 for compatibility)
			result_mulu(127 downto 0) <= (faktorA(31 downto 16) & faktorA(31 downto 0) & reg_QA(15 downto 0)) * (faktorB(31 downto 16) & faktorB(31 downto 0) & OP2out(15 downto 0));
		END IF;
	ELSE
		-- Iterative multiplier implementation (Booth-like algorithm)
		-- Sign extension for signed operations
		IF (signedOP='1' AND faktorB(31)='1') OR FAsign='1' THEN
			muls_msb <= mulu_reg(63);
		ELSE
			muls_msb <= '0';
		END IF;	
		
		IF signedOP='1' AND faktorB(31)='1' THEN
			mulu_sign <= '1';
		ELSE
			mulu_sign <= '0';
		END IF;	
		
		-- Shift and add/subtract based on LSB
		IF MUL_Mode=0 THEN	-- 16-bit mode
			result_mulu(63 downto 32) <= muls_msb&mulu_reg(63 downto 33);	
			result_mulu(15 downto 0) <= 'X'&mulu_reg(15 downto 1);	
			IF mulu_reg(0)='1' THEN
				IF FAsign='1' THEN  -- Subtract for negative multiplicand
					result_mulu(63 downto 47) <= (muls_msb&mulu_reg(63 downto 48)-(mulu_sign&faktorB(31 downto 16)));	
				ELSE
					result_mulu(63 downto 47) <= (muls_msb&mulu_reg(63 downto 48)+(mulu_sign&faktorB(31 downto 16)));	
				END IF;
			END IF;	
		ELSE				-- 32-bit mode
			result_mulu(63 downto 0) <= muls_msb&mulu_reg(63 downto 1);	
			IF mulu_reg(0)='1' THEN
				IF FAsign='1' THEN
					result_mulu(63 downto 31) <= (muls_msb&mulu_reg(63 downto 32)-(mulu_sign&faktorB));	
				ELSE
					result_mulu(63 downto 31) <= (muls_msb&mulu_reg(63 downto 32)+(mulu_sign&faktorB));	
				END IF;
			END IF;	
		END IF;
		
		-- Prepare factor B
		IF exe_opcode(15)='1' OR MUL_Mode=0 THEN
			faktorB(31 downto 16) <= OP2out(15 downto 0);
			faktorB(15 downto 0) <= (OTHERS=>'0');
		ELSE	
			faktorB <= OP2out;
		END IF;
	END IF;
	
		-- Calculate multiply overflow flag
		-- V is set if upper 32 bits are not sign extension of lower 32
		IF (result_mulu(63 downto 32)=X"00000000" AND (signedOP='0' OR result_mulu(31)='0')) OR
			(result_mulu(63 downto 32)=X"FFFFFFFF" AND signedOP='1' AND result_mulu(31)='1') THEN
			set_mV_Flag <= '0';
		ELSE	
			set_mV_Flag <= '1';
		END IF;
	END PROCESS;
	
PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF clkena_lw='1' THEN
				IF MUL_Hardware=0 THEN
					-- Initialize iterative multiplier
					IF micro_state=mul1 THEN
						mulu_reg(63 downto 32) <= (OTHERS=>'0');
						-- Handle negative multiplicand for signed multiply
						IF divs='1' AND ((exe_opcode(15)='1' AND reg_QA(15)='1') OR (exe_opcode(15)='0' AND reg_QA(31)='1')) THEN
							FAsign <= '1';
							mulu_reg(31 downto 0) <= 0-reg_QA;  -- Two's complement
						ELSE
							FAsign <= '0';
							mulu_reg(31 downto 0) <= reg_QA;
						END IF;	
					ELSIF exec(opcMULU)='0' THEN
						mulu_reg <= result_mulu(63 downto 0);	
					END IF;
				ELSE	
					-- Hardware multiplier: store upper result
					mulu_reg(31 downto 0) <= result_mulu(63 downto 32);
				END IF;
			END IF;
		END IF;
	END PROCESS;
		
-------------------------------------------------------------------------------
-- Division Unit
-- Implements restoring division algorithm
-- Supports 16/32-bit operations, signed and unsigned
-------------------------------------------------------------------------------
		
PROCESS (execOPC, OP1out, OP2out, div_reg, div_neg, div_bit, div_sub, div_quot, OP1_sign, div_over, result_div, reg_QA, opcode, sndOPC, divs, exe_opcode, reg_QB, 
	     signedOP, nozero, div_qsign, OP2outext, result_div_pre)
	BEGIN
		-- Determine if signed division
		divs <= (opcode(15) AND opcode(8)) OR (NOT opcode(15) AND sndOPC(11));
		
		-- Prepare dividend
		dividend(15 downto 0) <= (OTHERS=> '0');
		dividend(63 downto 32) <= (OTHERS=> divs AND reg_QA(31));  -- Sign extend for DIVS
		IF exe_opcode(15)='1' OR DIV_Mode=0 THEN --DIV.W
			dividend(47 downto 16) <= reg_QA;
			div_qsign <= result_div_pre(15);
		ELSE												  --DIV.l
			dividend(31 downto 0) <= reg_QA;
			-- 64-bit dividend for DIVSL
			IF exe_opcode(14)='1' AND sndOPC(10)='1' THEN
				dividend(63 downto 32) <= reg_QB;
			END IF;
			div_qsign <= result_div_pre(31);
		END IF;
		
		-- Sign extend divisor for signed operations
		IF signedOP='1' OR opcode(15)='0' THEN 
			OP2outext <= OP2out(31 downto 16);
		ELSE
			OP2outext <= (OTHERS=> '0');
		END IF;
		
		-- Perform trial subtraction
		IF signedOP='1' AND OP2out(31) ='1' THEN
			div_sub <= (div_reg(63 downto 31))+('1'&OP2out(31 downto 0));  -- Add for negative divisor
		ELSE
			div_sub <= (div_reg(63 downto 31))-('0'&OP2outext(15 downto 0)&OP2out(15 downto 0));
		END IF;	
		
		-- Check if subtraction successful
		IF DIV_Mode=0 THEN
			div_bit <= div_sub(16);
		ELSE
			div_bit <= div_sub(32);
		END IF;
		
		-- Update quotient and remainder
		IF div_bit='1' THEN
			div_quot(63 downto 32) <= div_reg(62 downto 31);	-- Restore
		ELSE
			div_quot(63 downto 32) <= div_sub(31 downto 0);	-- Keep subtraction
		END IF;	
		div_quot(31 downto 0) <= div_reg(30 downto 0)&NOT div_bit;  -- Shift in quotient bit
		
		-- Apply sign to quotient if needed
		IF div_neg='1' THEN
			result_div_pre(31 downto 0) <= 0-div_quot(31 downto 0);
		ELSE
			result_div_pre(31 downto 0) <= div_quot(31 downto 0);
		END IF;	
		
		-- Check for division overflow
		IF (((nozero='1' OR div_bit='0') AND signedOP='1' AND (OP2out(31) XOR OP1_sign XOR div_qsign)='1' )	--Overflow DIVS
			OR (signedOP='0' AND div_over(32)='0')) AND DIV_Mode/=3 THEN	--Overflow DIVU
			set_V_Flag <= '1';
		ELSE	
			set_V_Flag <= '0';
		END IF;
	END PROCESS;
	
PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF clkena_lw='1' THEN
				IF micro_state/=div_end2 THEN
					V_Flag <= set_V_Flag;
				END IF;
				signedOP <= divs;
				IF micro_state=div1 THEN
					nozero <= '0';
					-- Handle negative dividend for signed division
					IF divs='1' AND dividend(63)='1' THEN
						OP1_sign <= '1';
						div_reg <= 0-dividend;
					ELSE
						OP1_sign <= '0';
						div_reg <= dividend;
					END IF;	
				ELSE
					div_reg <= div_quot;	
					nozero <= NOT div_bit OR nozero;  -- Track non-zero quotient
				END IF;
				IF micro_state=div2 THEN
					-- Determine final quotient sign
					div_neg <= signedOP AND (OP2out(31) XOR OP1_sign);
					-- Check for overflow (divisor > upper long of dividend)
					IF DIV_Mode=0 THEN
						div_over(32 downto 16) <= ('0'&div_reg(47 downto 32))-('0'&OP2out(15 downto 0));
					ELSE	
						div_over <= ('0'&div_reg(63 downto 32))-('0'&OP2outext(15 downto 0)&OP2out(15 downto 0));
					END IF;	
				END IF;
				-- Store final quotient and remainder
				IF exec(write_reminder)='0' THEN
					result_div(31 downto 0) <= result_div_pre;
					-- Apply sign to remainder
					IF OP1_sign='1' THEN
						result_div(63 downto 32) <= 0-div_quot(63 downto 32);
					ELSE
						result_div(63 downto 32) <= div_quot(63 downto 32);
					END IF;	
				END IF;
			END IF;
		END IF;
	END PROCESS;
END;
