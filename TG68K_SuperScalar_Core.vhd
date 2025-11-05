------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K SuperScalar 4-Issue Core                                          --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Top-level superscalar processor core integrating all components         --
-- - 4-wide fetch, decode, and dispatch                                    --
-- - Out-of-order execution with 4 execution units                         --
-- - In-order commit via Reorder Buffer                                    --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_SuperScalar_Core is
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
        clk             : in std_logic;
        nReset          : in std_logic;
        clkena_in       : in std_logic := '1';
        data_in         : in std_logic_vector(15 downto 0);
        IPL             : in std_logic_vector(2 downto 0) := "111";
        IPL_autovector  : in std_logic := '0';
        berr            : in std_logic := '0';
        CPU             : in std_logic_vector(1 downto 0) := "00";
        addr_out        : out std_logic_vector(31 downto 0);
        data_write      : out std_logic_vector(15 downto 0);
        nWr             : out std_logic;
        nUDS            : out std_logic;
        nLDS            : out std_logic;
        busstate        : out std_logic_vector(1 downto 0);
        longword        : out std_logic;
        nResetOut       : out std_logic;
        FC              : out std_logic_vector(2 downto 0);
        clr_berr        : out std_logic;
        skipFetch       : out std_logic;
        regin_out       : out std_logic_vector(31 downto 0);
        CACR_out        : out std_logic_vector(3 downto 0);
        VBR_out         : out std_logic_vector(31 downto 0)
    );
end TG68K_SuperScalar_Core;

architecture rtl of TG68K_SuperScalar_Core is

    -- Components
    component TG68K_InstructionFetch is
        port(
            clk : in std_logic; reset : in std_logic; enable : in std_logic;
            pc_in : in std_logic_vector(31 downto 0); pc_update : in std_logic;
            pc_new : in std_logic_vector(31 downto 0); fetch_stall : in std_logic;
            flush_pipeline : in std_logic; mem_addr : out std_logic_vector(31 downto 0);
            mem_read : out std_logic; mem_data : in std_logic_vector(63 downto 0);
            mem_ready : in std_logic; fetch_valid : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
            fetch_pc : out std_logic_vector(31 downto 0); fetch_inst : out fetch_buffer_t
        );
    end component;

    component TG68K_Decode is
        port(
            clk : in std_logic; reset : in std_logic; enable : in std_logic;
            fetch_valid : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            fetch_pc : in std_logic_vector(31 downto 0); fetch_inst : in fetch_buffer_t;
            decoded_valid : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
            decoded_inst : out decoded_inst_array_t; decode_stall : in std_logic
        );
    end component;

    component TG68K_RegisterRename is
        port(
            clk : in std_logic; reset : in std_logic; enable : in std_logic;
            decoded_valid : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            decoded_inst : in decoded_inst_array_t;
            src1_preg : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            src2_preg : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            dest_preg : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            old_dest_preg : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            alloc_success : out std_logic;
            commit_valid : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            commit_preg : in array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            flush : in std_logic; checkpoint_restore : in std_logic
        );
    end component;

    component TG68K_ReorderBuffer is
        port(
            clk : in std_logic; reset : in std_logic; enable : in std_logic;
            dispatch_valid : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            dispatch_inst : in decoded_inst_array_t;
            dispatch_dest_preg : in array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            dispatch_old_preg : in array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            rob_full : out std_logic; rob_tail : out integer range 0 to ROB_SIZE-1;
            alloc_rob_index : out array(0 to ISSUE_WIDTH-1) of integer range 0 to ROB_SIZE-1;
            complete_valid : in std_logic_vector(EU_COUNT-1 downto 0);
            complete_rob_idx : in array(0 to EU_COUNT-1) of integer range 0 to ROB_SIZE-1;
            complete_result : in array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
            complete_exception : in std_logic_vector(EU_COUNT-1 downto 0);
            commit_valid : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
            commit_dest_reg : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(3 downto 0);
            commit_dest_preg : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            commit_old_preg : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            commit_result : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(31 downto 0);
            commit_pc : out array(0 to ISSUE_WIDTH-1) of std_logic_vector(31 downto 0);
            branch_mispredict : out std_logic; branch_target : out std_logic_vector(31 downto 0);
            flush_pipeline : out std_logic; exception_valid : out std_logic;
            exception_pc : out std_logic_vector(31 downto 0);
            exception_vector : out std_logic_vector(7 downto 0)
        );
    end component;

    component TG68K_ReservationStation is
        port(
            clk : in std_logic; reset : in std_logic; enable : in std_logic;
            dispatch_valid : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            dispatch_inst : in decoded_inst_array_t;
            dispatch_rob_idx : in array(0 to ISSUE_WIDTH-1) of integer range 0 to ROB_SIZE-1;
            dispatch_src1_preg : in array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            dispatch_src2_preg : in array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            dispatch_dest_preg : in array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
            rs_full : out std_logic;
            prf_read_addr : out array(0 to ISSUE_WIDTH*2-1) of std_logic_vector(5 downto 0);
            prf_read_data : in array(0 to ISSUE_WIDTH*2-1) of std_logic_vector(31 downto 0);
            broadcast_valid : in std_logic_vector(EU_COUNT-1 downto 0);
            broadcast_preg : in array(0 to EU_COUNT-1) of std_logic_vector(5 downto 0);
            broadcast_data : in array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
            issue_valid : out std_logic_vector(EU_COUNT-1 downto 0);
            issue_opcode : out array(0 to EU_COUNT-1) of std_logic_vector(15 downto 0);
            issue_pc : out array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
            issue_rob_idx : out array(0 to EU_COUNT-1) of integer range 0 to ROB_SIZE-1;
            issue_src1 : out array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
            issue_src2 : out array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
            issue_imm : out array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
            eu_busy : in std_logic_vector(EU_COUNT-1 downto 0);
            flush : in std_logic
        );
    end component;

    component TG68K_ExecutionUnit is
        generic(EU_TYPE : integer := EU_ALU0);
        port(
            clk : in std_logic; reset : in std_logic; enable : in std_logic;
            issue_valid : in std_logic; issue_opcode : in std_logic_vector(15 downto 0);
            issue_pc : in std_logic_vector(31 downto 0);
            issue_rob_idx : in integer range 0 to ROB_SIZE-1;
            issue_src1 : in std_logic_vector(31 downto 0);
            issue_src2 : in std_logic_vector(31 downto 0);
            issue_imm : in std_logic_vector(31 downto 0); eu_busy : out std_logic;
            complete_valid : out std_logic;
            complete_rob_idx : out integer range 0 to ROB_SIZE-1;
            complete_result : out std_logic_vector(31 downto 0);
            complete_exception : out std_logic;
            mem_addr : out std_logic_vector(31 downto 0); mem_write : out std_logic;
            mem_read : out std_logic; mem_data_out : out std_logic_vector(31 downto 0);
            mem_data_in : in std_logic_vector(31 downto 0); mem_ready : in std_logic
        );
    end component;

    component TG68K_PhysicalRegFile is
        port(
            clk : in std_logic; reset : in std_logic; enable : in std_logic;
            read_addr : in array(0 to 7) of std_logic_vector(5 downto 0);
            read_data : out array(0 to 7) of std_logic_vector(31 downto 0);
            write_enable : in std_logic_vector(3 downto 0);
            write_addr : in array(0 to 3) of std_logic_vector(5 downto 0);
            write_data : in array(0 to 3) of std_logic_vector(31 downto 0);
            broadcast_enable : in std_logic_vector(EU_COUNT-1 downto 0);
            broadcast_addr : in array(0 to EU_COUNT-1) of std_logic_vector(5 downto 0);
            broadcast_data : in array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0)
        );
    end component;

    -- Internal signals
    signal reset : std_logic;
    signal pc_reg : std_logic_vector(31 downto 0);

    -- Fetch stage signals
    signal fetch_valid : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal fetch_pc : std_logic_vector(31 downto 0);
    signal fetch_inst : fetch_buffer_t;
    signal fetch_stall : std_logic;
    signal flush_pipeline : std_logic;

    -- Decode stage signals
    signal decoded_valid : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal decoded_inst : decoded_inst_array_t;

    -- Register rename signals
    signal src1_preg : array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
    signal src2_preg : array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
    signal dest_preg : array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
    signal old_dest_preg : array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
    signal rename_success : std_logic;

    -- ROB signals
    signal rob_full : std_logic;
    signal alloc_rob_index : array(0 to ISSUE_WIDTH-1) of integer range 0 to ROB_SIZE-1;
    signal commit_valid : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal commit_dest_preg : array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
    signal commit_old_preg : array(0 to ISSUE_WIDTH-1) of std_logic_vector(5 downto 0);
    signal commit_result : array(0 to ISSUE_WIDTH-1) of std_logic_vector(31 downto 0);

    -- RS signals
    signal rs_full : std_logic;
    signal issue_valid : std_logic_vector(EU_COUNT-1 downto 0);
    signal issue_opcode : array(0 to EU_COUNT-1) of std_logic_vector(15 downto 0);
    signal issue_pc : array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
    signal issue_rob_idx : array(0 to EU_COUNT-1) of integer range 0 to ROB_SIZE-1;
    signal issue_src1 : array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
    signal issue_src2 : array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
    signal issue_imm : array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);

    -- EU signals
    signal eu_busy : std_logic_vector(EU_COUNT-1 downto 0);
    signal complete_valid : std_logic_vector(EU_COUNT-1 downto 0);
    signal complete_rob_idx : array(0 to EU_COUNT-1) of integer range 0 to ROB_SIZE-1;
    signal complete_result : array(0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
    signal complete_exception : std_logic_vector(EU_COUNT-1 downto 0);

    -- PRF signals
    signal prf_read_addr : array(0 to 7) of std_logic_vector(5 downto 0);
    signal prf_read_data : array(0 to 7) of std_logic_vector(31 downto 0);
    signal prf_write_enable : std_logic_vector(3 downto 0);

    -- Memory interface (simplified)
    signal mem_data_64 : std_logic_vector(63 downto 0);
    signal mem_ready : std_logic;

begin

    reset <= not nReset;
    nResetOut <= nReset;
    skipFetch <= '0';

    -- Stall conditions
    fetch_stall <= rob_full or rs_full or (not rename_success);

    -- Memory interface (simplified - needs proper implementation)
    mem_data_64 <= data_in & data_in & data_in & data_in;
    mem_ready <= clkena_in;

    -- Instantiate Instruction Fetch
    inst_fetch: TG68K_InstructionFetch
        port map(
            clk => clk, reset => reset, enable => clkena_in,
            pc_in => pc_reg, pc_update => flush_pipeline,
            pc_new => (others => '0'), fetch_stall => fetch_stall,
            flush_pipeline => flush_pipeline,
            mem_addr => addr_out, mem_read => open,
            mem_data => mem_data_64, mem_ready => mem_ready,
            fetch_valid => fetch_valid, fetch_pc => fetch_pc,
            fetch_inst => fetch_inst
        );

    -- Instantiate Decode
    inst_decode: TG68K_Decode
        port map(
            clk => clk, reset => reset, enable => clkena_in,
            fetch_valid => fetch_valid, fetch_pc => fetch_pc,
            fetch_inst => fetch_inst, decoded_valid => decoded_valid,
            decoded_inst => decoded_inst, decode_stall => fetch_stall
        );

    -- Instantiate Register Rename
    inst_rename: TG68K_RegisterRename
        port map(
            clk => clk, reset => reset, enable => clkena_in,
            decoded_valid => decoded_valid, decoded_inst => decoded_inst,
            src1_preg => src1_preg, src2_preg => src2_preg,
            dest_preg => dest_preg, old_dest_preg => old_dest_preg,
            alloc_success => rename_success,
            commit_valid => commit_valid, commit_preg => commit_old_preg,
            flush => flush_pipeline, checkpoint_restore => '0'
        );

    -- Instantiate ROB
    inst_rob: TG68K_ReorderBuffer
        port map(
            clk => clk, reset => reset, enable => clkena_in,
            dispatch_valid => decoded_valid, dispatch_inst => decoded_inst,
            dispatch_dest_preg => dest_preg, dispatch_old_preg => old_dest_preg,
            rob_full => rob_full, rob_tail => open,
            alloc_rob_index => alloc_rob_index,
            complete_valid => complete_valid, complete_rob_idx => complete_rob_idx,
            complete_result => complete_result, complete_exception => complete_exception,
            commit_valid => commit_valid, commit_dest_reg => open,
            commit_dest_preg => commit_dest_preg, commit_old_preg => commit_old_preg,
            commit_result => commit_result, commit_pc => open,
            branch_mispredict => open, branch_target => open,
            flush_pipeline => flush_pipeline, exception_valid => open,
            exception_pc => open, exception_vector => open
        );

    -- Instantiate Reservation Station
    inst_rs: TG68K_ReservationStation
        port map(
            clk => clk, reset => reset, enable => clkena_in,
            dispatch_valid => decoded_valid, dispatch_inst => decoded_inst,
            dispatch_rob_idx => alloc_rob_index,
            dispatch_src1_preg => src1_preg, dispatch_src2_preg => src2_preg,
            dispatch_dest_preg => dest_preg, rs_full => rs_full,
            prf_read_addr => prf_read_addr, prf_read_data => prf_read_data,
            broadcast_valid => complete_valid, broadcast_preg => dest_preg(0 to EU_COUNT-1),
            broadcast_data => complete_result,
            issue_valid => issue_valid, issue_opcode => issue_opcode,
            issue_pc => issue_pc, issue_rob_idx => issue_rob_idx,
            issue_src1 => issue_src1, issue_src2 => issue_src2,
            issue_imm => issue_imm, eu_busy => eu_busy, flush => flush_pipeline
        );

    -- Instantiate Execution Units
    gen_eus: for i in 0 to EU_COUNT-1 generate
        inst_eu: TG68K_ExecutionUnit
            generic map(EU_TYPE => i)
            port map(
                clk => clk, reset => reset, enable => clkena_in,
                issue_valid => issue_valid(i), issue_opcode => issue_opcode(i),
                issue_pc => issue_pc(i), issue_rob_idx => issue_rob_idx(i),
                issue_src1 => issue_src1(i), issue_src2 => issue_src2(i),
                issue_imm => issue_imm(i), eu_busy => eu_busy(i),
                complete_valid => complete_valid(i), complete_rob_idx => complete_rob_idx(i),
                complete_result => complete_result(i), complete_exception => complete_exception(i),
                mem_addr => open, mem_write => open, mem_read => open,
                mem_data_out => open, mem_data_in => (others => '0'), mem_ready => mem_ready
            );
    end generate;

    -- Instantiate Physical Register File
    inst_prf: TG68K_PhysicalRegFile
        port map(
            clk => clk, reset => reset, enable => clkena_in,
            read_addr => prf_read_addr, read_data => prf_read_data,
            write_enable => prf_write_enable, write_addr => commit_dest_preg,
            write_data => commit_result,
            broadcast_enable => complete_valid, broadcast_addr => dest_preg(0 to EU_COUNT-1),
            broadcast_data => complete_result
        );

    -- Generate write enables from commit valid
    prf_write_enable <= commit_valid;

    -- Output assignments (simplified)
    busstate <= "01";
    nWr <= '1';
    nUDS <= '1';
    nLDS <= '1';
    longword <= '0';
    FC <= "000";
    clr_berr <= '0';
    data_write <= (others => '0');
    regin_out <= (others => '0');
    CACR_out <= (others => '0');
    VBR_out <= (others => '0');

end rtl;
