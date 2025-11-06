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
            src1_preg : out preg_array_t;
            src2_preg : out preg_array_t;
            dest_preg : out preg_array_t;
            old_dest_preg : out preg_array_t;
            alloc_success : out std_logic;
            commit_valid : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            commit_preg : in preg_array_t;
            flush : in std_logic; checkpoint_restore : in std_logic
        );
    end component;

    component TG68K_ReorderBuffer is
        port(
            clk : in std_logic; reset : in std_logic; enable : in std_logic;
            dispatch_valid : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            dispatch_inst : in decoded_inst_array_t;
            dispatch_dest_preg : in preg_array_t;
            dispatch_old_preg : in preg_array_t;
            rob_full : out std_logic; rob_tail : out integer range 0 to ROB_SIZE-1;
            alloc_rob_index : out rob_idx_array_t;
            complete_valid : in std_logic_vector(EU_COUNT-1 downto 0);
            complete_rob_idx : in eu_rob_idx_array_t;
            complete_result : in eu_data_array_t;
            complete_exception : in std_logic_vector(EU_COUNT-1 downto 0);
            complete_dest_preg : out eu_preg_array_t;
            commit_valid : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
            commit_dest_reg : out reg_array_t;
            commit_dest_preg : out preg_array_t;
            commit_old_preg : out preg_array_t;
            commit_result : out data_array_t;
            commit_pc : out pc_array_t;
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
            dispatch_rob_idx : in rob_idx_array_t;
            dispatch_src1_preg : in preg_array_t;
            dispatch_src2_preg : in preg_array_t;
            dispatch_dest_preg : in preg_array_t;
            rs_full : out std_logic;
            prf_read_addr : out prf_addr_array_t;
            prf_read_data : in prf_data_array_t;
            broadcast_valid : in std_logic_vector(EU_COUNT-1 downto 0);
            broadcast_preg : in eu_preg_array_t;
            broadcast_data : in eu_data_array_t;
            issue_valid : out std_logic_vector(EU_COUNT-1 downto 0);
            issue_opcode : out eu_opcode_array_t;
            issue_pc : out eu_pc_array_t;
            issue_rob_idx : out eu_rob_idx_array_t;
            issue_src1 : out eu_data_array_t;
            issue_src2 : out eu_data_array_t;
            issue_imm : out eu_data_array_t;
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
            read_addr : in prf_read_array_t;
            read_data : out prf_rdata_array_t;
            write_enable : in std_logic_vector(3 downto 0);
            write_addr : in prf_write_array_t;
            write_data : in prf_wdata_array_t;
            broadcast_enable : in std_logic_vector(EU_COUNT-1 downto 0);
            broadcast_addr : in eu_preg_array_t;
            broadcast_data : in eu_data_array_t
        );
    end component;

    -- Internal signals
    signal reset : std_logic;
    signal pc_reg : std_logic_vector(31 downto 0);
    signal pc_update : std_logic;
    signal pc_new : std_logic_vector(31 downto 0);

    -- Fetch stage signals
    signal fetch_valid : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal fetch_pc : std_logic_vector(31 downto 0);
    signal fetch_inst : fetch_buffer_t;
    signal fetch_stall : std_logic;
    signal flush_pipeline : std_logic;

    -- Branch/Exception signals
    signal branch_mispredict : std_logic;
    signal branch_target : std_logic_vector(31 downto 0);
    signal exception_valid : std_logic;
    signal exception_pc : std_logic_vector(31 downto 0);
    signal exception_vector : std_logic_vector(7 downto 0);

    -- Decode stage signals
    signal decoded_valid : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal decoded_inst : decoded_inst_array_t;

    -- Register rename signals
    signal src1_preg : preg_array_t;
    signal src2_preg : preg_array_t;
    signal dest_preg : preg_array_t;
    signal old_dest_preg : preg_array_t;
    signal rename_success : std_logic;

    -- ROB signals
    signal rob_full : std_logic;
    signal alloc_rob_index : rob_idx_array_t;
    signal commit_valid : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal commit_dest_preg : preg_array_t;
    signal commit_old_preg : preg_array_t;
    signal commit_result : data_array_t;

    -- RS signals
    signal rs_full : std_logic;
    signal issue_valid : std_logic_vector(EU_COUNT-1 downto 0);
    signal issue_opcode : eu_opcode_array_t;
    signal issue_pc : eu_pc_array_t;
    signal issue_rob_idx : eu_rob_idx_array_t;
    signal issue_src1 : eu_data_array_t;
    signal issue_src2 : eu_data_array_t;
    signal issue_imm : eu_data_array_t;

    -- EU signals
    signal eu_busy : std_logic_vector(EU_COUNT-1 downto 0);
    signal complete_valid : std_logic_vector(EU_COUNT-1 downto 0);
    signal complete_rob_idx : eu_rob_idx_array_t;
    signal complete_result : eu_data_array_t;
    signal complete_exception : std_logic_vector(EU_COUNT-1 downto 0);
    signal complete_dest_preg : eu_preg_array_t;  -- Dest preg from ROB for broadcast

    -- Memory interface signals (from LSU execution unit)
    type mem_addr_array_t is array (0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
    type mem_data_array_t is array (0 to EU_COUNT-1) of std_logic_vector(31 downto 0);
    signal eu_mem_addr : mem_addr_array_t;
    signal eu_mem_write : std_logic_vector(EU_COUNT-1 downto 0);
    signal eu_mem_read : std_logic_vector(EU_COUNT-1 downto 0);
    signal eu_mem_data_out : mem_data_array_t;

    -- PRF signals
    signal prf_read_addr : prf_read_array_t;
    signal prf_read_data : prf_rdata_array_t;
    signal prf_write_enable : std_logic_vector(3 downto 0);
    signal prf_write_addr : prf_write_array_t;
    signal prf_write_data : prf_wdata_array_t;

    -- Memory interface (simplified)
    signal mem_data_64 : std_logic_vector(63 downto 0);
    signal mem_data_32 : std_logic_vector(31 downto 0);  -- Extended to 32-bit for EUs
    signal mem_ready : std_logic;
    signal if_mem_read : std_logic;  -- Instruction fetch memory read request
    signal if_mem_addr : std_logic_vector(31 downto 0);  -- Instruction fetch address

begin

    reset <= not nReset;
    nResetOut <= nReset;
    skipFetch <= '0';

    -- Stall conditions
    fetch_stall <= rob_full or rs_full or (not rename_success);

    -- PC update logic (handles branches, exceptions, and sequential fetch)
    pc_update <= branch_mispredict or exception_valid or flush_pipeline;

    process(branch_mispredict, exception_valid, branch_target, exception_vector, pc_reg)
    begin
        if exception_valid = '1' then
            -- Exception: jump to exception vector (simplified - should use VBR)
            pc_new <= x"000000" & exception_vector;
        elsif branch_mispredict = '1' then
            -- Branch misprediction: use correct branch target
            pc_new <= branch_target;
        else
            -- Sequential: increment by 8 (4 instructions * 2 bytes)
            pc_new <= std_logic_vector(unsigned(pc_reg) + 8);
        end if;
    end process;

    -- PC register update
    process(clk, reset)
    begin
        if reset = '1' then
            pc_reg <= x"00000000";
        elsif rising_edge(clk) then
            if clkena_in = '1' then
                if pc_update = '1' then
                    pc_reg <= pc_new;
                elsif fetch_stall = '0' then
                    -- Sequential increment when fetching
                    pc_reg <= std_logic_vector(unsigned(pc_reg) + 8);
                end if;
            end if;
        end if;
    end process;

    -- Type conversion for PRF write interface
    process(commit_dest_preg, commit_result)
    begin
        for i in 0 to 3 loop
            prf_write_addr(i) <= commit_dest_preg(i);
            prf_write_data(i) <= commit_result(i);
        end loop;
    end process;

    -- Memory interface (simplified - needs proper implementation)
    mem_data_64 <= data_in & data_in & data_in & data_in;
    mem_data_32 <= x"0000" & data_in;  -- Extend 16-bit to 32-bit
    mem_ready <= clkena_in;

    -- Instantiate Instruction Fetch
    inst_fetch: TG68K_InstructionFetch
        port map(
            clk => clk, reset => reset, enable => clkena_in,
            pc_in => pc_reg, pc_update => pc_update,
            pc_new => pc_new, fetch_stall => fetch_stall,
            flush_pipeline => flush_pipeline,
            mem_addr => if_mem_addr, mem_read => if_mem_read,
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
            complete_dest_preg => complete_dest_preg,
            commit_valid => commit_valid, commit_dest_reg => open,
            commit_dest_preg => commit_dest_preg, commit_old_preg => commit_old_preg,
            commit_result => commit_result, commit_pc => open,
            branch_mispredict => branch_mispredict, branch_target => branch_target,
            flush_pipeline => flush_pipeline, exception_valid => exception_valid,
            exception_pc => exception_pc, exception_vector => exception_vector
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
            broadcast_valid => complete_valid, broadcast_preg => complete_dest_preg,
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
                mem_addr => eu_mem_addr(i), mem_write => eu_mem_write(i), mem_read => eu_mem_read(i),
                mem_data_out => eu_mem_data_out(i), mem_data_in => mem_data_32, mem_ready => mem_ready
            );
    end generate;

    -- Memory interface mux (mux between instruction fetch and LSU)
    process(if_mem_addr, if_mem_read, eu_mem_addr, eu_mem_write, eu_mem_read, eu_mem_data_out)
    begin
        -- Default: no memory access
        nWr <= '1';
        nUDS <= '1';
        nLDS <= '1';
        data_write <= (others => '0');
        addr_out <= (others => '0');
        busstate <= "01";  -- Idle

        -- Priority: LSU takes precedence over instruction fetch
        if eu_mem_write(EU_LSU) = '1' or eu_mem_read(EU_LSU) = '1' then
            -- LSU (EU_LSU = 2) drives memory interface
            addr_out <= eu_mem_addr(EU_LSU);
            data_write <= eu_mem_data_out(EU_LSU)(15 downto 0);

            if eu_mem_write(EU_LSU) = '1' then
                nWr <= '0';
                nUDS <= '0';
                nLDS <= '0';
                busstate <= "11";  -- Write
            else
                nWr <= '1';
                nUDS <= '0';
                nLDS <= '0';
                busstate <= "10";  -- Read
            end if;
        elsif if_mem_read = '1' then
            -- Instruction fetch drives memory interface
            addr_out <= if_mem_addr;
            nWr <= '1';
            nUDS <= '0';
            nLDS <= '0';
            busstate <= "10";  -- Read
        end if;
    end process;

    -- Instantiate Physical Register File
    inst_prf: TG68K_PhysicalRegFile
        port map(
            clk => clk, reset => reset, enable => clkena_in,
            read_addr => prf_read_addr, read_data => prf_read_data,
            write_enable => prf_write_enable, write_addr => prf_write_addr,
            write_data => prf_write_data,
            broadcast_enable => complete_valid, broadcast_addr => complete_dest_preg,
            broadcast_data => complete_result
        );

    -- Generate write enables from commit valid
    prf_write_enable <= commit_valid;

    -- Output assignments (simplified)
    longword <= '0';
    FC <= "000";
    clr_berr <= '0';
    regin_out <= (others => '0');
    CACR_out <= (others => '0');
    VBR_out <= (others => '0');

end rtl;
