--------------------------------------------------------------------------------
-- TG68K Superscalar Core (Top Level Integration)
-- 8-issue superscalar 68K processor with out-of-order execution
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Superscalar_Pack.all;

entity TG68K_Superscalar_Core is
    port (
        clk             : in std_logic;
        reset           : in std_logic;

        -- Instruction cache interface
        icache_addr     : out std_logic_vector(31 downto 0);
        icache_req      : out std_logic;
        icache_data     : in std_logic_vector(255 downto 0);
        icache_valid    : in std_logic;

        -- Data cache interface
        dcache_addr     : out std_logic_vector(31 downto 0);
        dcache_data_out : out std_logic_vector(31 downto 0);
        dcache_data_in  : in std_logic_vector(31 downto 0);
        dcache_read     : out std_logic;
        dcache_write    : out std_logic;
        dcache_size     : out std_logic_vector(1 downto 0);
        dcache_ready    : in std_logic;

        -- Interrupt interface
        ipl             : in std_logic_vector(2 downto 0);

        -- Debug/Status
        debug_pc        : out std_logic_vector(31 downto 0);
        debug_rob_count : out integer range 0 to ROB_SIZE;
        debug_commits   : out integer range 0 to ISSUE_WIDTH
    );
end entity TG68K_Superscalar_Core;

architecture rtl of TG68K_Superscalar_Core is

    -- Pipeline stage signals
    signal fetch_instr      : instruction_array_t;
    signal fetch_valid      : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal fetch_pc         : std_logic_vector(31 downto 0);

    signal decode_instr     : instruction_array_t;
    signal decode_valid     : std_logic_vector(ISSUE_WIDTH-1 downto 0);

    signal rename_instr     : instruction_array_t;
    signal rename_valid     : std_logic_vector(ISSUE_WIDTH-1 downto 0);

    signal issue_instr      : instruction_array_t;
    signal issue_valid      : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal issue_src1       : exec_result_array_t;
    signal issue_src2       : exec_result_array_t;

    signal complete_valid   : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal complete_result  : exec_result_array_t;

    signal commit_valid     : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal commit_data      : commit_array_t;

    -- Control signals
    signal fetch_stall      : std_logic;
    signal decode_stall     : std_logic;
    signal rename_stall     : std_logic;
    signal issue_stall      : std_logic;

    signal flush            : std_logic;
    signal flush_pc         : std_logic_vector(31 downto 0);

    -- ROB signals
    signal rob_full         : std_logic;
    signal rob_head         : integer range 0 to ROB_SIZE-1;
    signal rob_tail         : integer range 0 to ROB_SIZE-1;
    signal branch_mispredict: std_logic;
    signal branch_flush_pc  : std_logic_vector(31 downto 0);

    -- Physical register file
    signal phys_reg_file    : phys_reg_file_t;
    signal phys_reg_ready   : std_logic_vector(PHYS_REGS-1 downto 0);

    -- Forwarding network
    signal forward_valid    : std_logic_vector(ISSUE_WIDTH-1 downto 0);
    signal forward_result   : exec_result_array_t;

    -- Execution unit status
    signal exec_busy        : std_logic_vector(ISSUE_WIDTH-1 downto 0);

    -- Reservation station status
    signal rs_full          : std_logic;

    -- Exception handling
    signal exception        : std_logic;
    signal exception_vec    : std_logic_vector(7 downto 0);
    signal exception_pc     : std_logic_vector(31 downto 0);

    -- Branch prediction update
    signal bp_update        : std_logic;
    signal bp_update_pc     : std_logic_vector(31 downto 0);
    signal bp_update_taken  : std_logic;
    signal bp_update_target : std_logic_vector(31 downto 0);

    -- Components
    component TG68K_Fetch_Unit is
        port (
            clk             : in std_logic;
            reset           : in std_logic;
            fetch_enable    : in std_logic;
            stall           : in std_logic;
            flush           : in std_logic;
            flush_pc        : in std_logic_vector(31 downto 0);
            icache_addr     : out std_logic_vector(31 downto 0);
            icache_req      : out std_logic;
            icache_data     : in std_logic_vector(255 downto 0);
            icache_valid    : in std_logic;
            bp_update       : in std_logic;
            bp_update_pc    : in std_logic_vector(31 downto 0);
            bp_update_taken : in std_logic;
            bp_update_target: in std_logic_vector(31 downto 0);
            fetch_instr     : out instruction_array_t;
            fetch_valid     : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
            fetch_pc        : out std_logic_vector(31 downto 0)
        );
    end component;

    component TG68K_Decode_Unit is
        port (
            clk             : in std_logic;
            reset           : in std_logic;
            fetch_instr     : in instruction_array_t;
            fetch_valid     : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            stall           : in std_logic;
            flush           : in std_logic;
            decode_instr    : out instruction_array_t;
            decode_valid    : out std_logic_vector(ISSUE_WIDTH-1 downto 0)
        );
    end component;

    component TG68K_Rename_Unit is
        port (
            clk             : in std_logic;
            reset           : in std_logic;
            decode_instr    : in instruction_array_t;
            decode_valid    : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            stall           : in std_logic;
            flush           : in std_logic;
            rob_head        : in integer range 0 to ROB_SIZE-1;
            rob_tail        : in integer range 0 to ROB_SIZE-1;
            rob_full        : in std_logic;
            commit_valid    : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            commit_arch_reg : in commit_array_t;
            rename_instr    : out instruction_array_t;
            rename_valid    : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
            phys_reg_ready  : in std_logic_vector(PHYS_REGS-1 downto 0)
        );
    end component;

    component TG68K_Issue_Logic is
        port (
            clk             : in std_logic;
            reset           : in std_logic;
            rename_instr    : in instruction_array_t;
            rename_valid    : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            phys_reg_file   : in phys_reg_file_t;
            forward_valid   : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            forward_result  : in exec_result_array_t;
            stall           : in std_logic;
            flush           : in std_logic;
            issue_valid     : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
            issue_instr     : out instruction_array_t;
            issue_src1      : out exec_result_array_t;
            issue_src2      : out exec_result_array_t;
            exec_busy       : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            rs_full         : out std_logic
        );
    end component;

    component TG68K_Exec_Units is
        port (
            clk             : in std_logic;
            reset           : in std_logic;
            issue_valid     : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            issue_instr     : in instruction_array_t;
            issue_src1      : in exec_result_array_t;
            issue_src2      : in exec_result_array_t;
            complete_valid  : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
            complete_result : out exec_result_array_t;
            forward_valid   : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
            forward_result  : out exec_result_array_t;
            mem_addr        : out std_logic_vector(31 downto 0);
            mem_data_out    : out std_logic_vector(31 downto 0);
            mem_data_in     : in std_logic_vector(31 downto 0);
            mem_read        : out std_logic;
            mem_write       : out std_logic;
            mem_size        : out std_logic_vector(1 downto 0);
            mem_ready       : in std_logic;
            exec_busy       : out std_logic_vector(ISSUE_WIDTH-1 downto 0)
        );
    end component;

    component TG68K_ROB is
        port (
            clk             : in std_logic;
            reset           : in std_logic;
            alloc_valid     : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            alloc_instr     : in instruction_array_t;
            complete_valid  : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
            complete_result : in exec_result_array_t;
            commit_valid    : out std_logic_vector(ISSUE_WIDTH-1 downto 0);
            commit_data     : out commit_array_t;
            branch_mispredict : out std_logic;
            branch_flush_pc   : out std_logic_vector(31 downto 0);
            rob_full        : out std_logic;
            rob_head        : out integer range 0 to ROB_SIZE-1;
            rob_tail        : out integer range 0 to ROB_SIZE-1;
            exception       : out std_logic;
            exception_vec   : out std_logic_vector(7 downto 0);
            exception_pc    : out std_logic_vector(31 downto 0)
        );
    end component;

begin

    -- =========================================================================
    -- Pipeline Control
    -- =========================================================================
    fetch_stall <= rob_full or rs_full;
    decode_stall <= rob_full or rs_full;
    rename_stall <= rob_full or rs_full;
    issue_stall <= '0';

    flush <= branch_mispredict or exception;
    flush_pc <= branch_flush_pc when branch_mispredict = '1' else exception_pc;

    -- Branch predictor update
    bp_update <= complete_valid(7) and complete_result(7).is_branch;
    bp_update_pc <= complete_result(7).pc when complete_valid(7) = '1' else (others => '0');
    bp_update_taken <= complete_result(7).branch_taken;
    bp_update_target <= complete_result(7).branch_target;

    -- Debug outputs
    debug_pc <= fetch_pc;
    debug_rob_count <= rob_tail - rob_head when rob_tail >= rob_head else
                       ROB_SIZE - (rob_head - rob_tail);
    debug_commits <= 0; -- Would count commit_valid bits

    -- =========================================================================
    -- Pipeline Stages
    -- =========================================================================

    fetch_unit_inst: TG68K_Fetch_Unit
        port map (
            clk             => clk,
            reset           => reset,
            fetch_enable    => '1',
            stall           => fetch_stall,
            flush           => flush,
            flush_pc        => flush_pc,
            icache_addr     => icache_addr,
            icache_req      => icache_req,
            icache_data     => icache_data,
            icache_valid    => icache_valid,
            bp_update       => bp_update,
            bp_update_pc    => bp_update_pc,
            bp_update_taken => bp_update_taken,
            bp_update_target => bp_update_target,
            fetch_instr     => fetch_instr,
            fetch_valid     => fetch_valid,
            fetch_pc        => fetch_pc
        );

    decode_unit_inst: TG68K_Decode_Unit
        port map (
            clk             => clk,
            reset           => reset,
            fetch_instr     => fetch_instr,
            fetch_valid     => fetch_valid,
            stall           => decode_stall,
            flush           => flush,
            decode_instr    => decode_instr,
            decode_valid    => decode_valid
        );

    rename_unit_inst: TG68K_Rename_Unit
        port map (
            clk             => clk,
            reset           => reset,
            decode_instr    => decode_instr,
            decode_valid    => decode_valid,
            stall           => rename_stall,
            flush           => flush,
            rob_head        => rob_head,
            rob_tail        => rob_tail,
            rob_full        => rob_full,
            commit_valid    => commit_valid,
            commit_arch_reg => commit_data,
            rename_instr    => rename_instr,
            rename_valid    => rename_valid,
            phys_reg_ready  => phys_reg_ready
        );

    issue_logic_inst: TG68K_Issue_Logic
        port map (
            clk             => clk,
            reset           => reset,
            rename_instr    => rename_instr,
            rename_valid    => rename_valid,
            phys_reg_file   => phys_reg_file,
            forward_valid   => forward_valid,
            forward_result  => forward_result,
            stall           => issue_stall,
            flush           => flush,
            issue_valid     => issue_valid,
            issue_instr     => issue_instr,
            issue_src1      => issue_src1,
            issue_src2      => issue_src2,
            exec_busy       => exec_busy,
            rs_full         => rs_full
        );

    exec_units_inst: TG68K_Exec_Units
        port map (
            clk             => clk,
            reset           => reset,
            issue_valid     => issue_valid,
            issue_instr     => issue_instr,
            issue_src1      => issue_src1,
            issue_src2      => issue_src2,
            complete_valid  => complete_valid,
            complete_result => complete_result,
            forward_valid   => forward_valid,
            forward_result  => forward_result,
            mem_addr        => dcache_addr,
            mem_data_out    => dcache_data_out,
            mem_data_in     => dcache_data_in,
            mem_read        => dcache_read,
            mem_write       => dcache_write,
            mem_size        => dcache_size,
            mem_ready       => dcache_ready,
            exec_busy       => exec_busy
        );

    rob_inst: TG68K_ROB
        port map (
            clk             => clk,
            reset           => reset,
            alloc_valid     => rename_valid,
            alloc_instr     => rename_instr,
            complete_valid  => complete_valid,
            complete_result => complete_result,
            commit_valid    => commit_valid,
            commit_data     => commit_data,
            branch_mispredict => branch_mispredict,
            branch_flush_pc   => branch_flush_pc,
            rob_full        => rob_full,
            rob_head        => rob_head,
            rob_tail        => rob_tail,
            exception       => exception,
            exception_vec   => exception_vec,
            exception_pc    => exception_pc
        );

    -- =========================================================================
    -- Physical Register File
    -- =========================================================================
    process(clk, reset)
    begin
        if reset = '1' then
            for i in 0 to PHYS_REGS-1 loop
                phys_reg_file(i).valid <= '1';
                phys_reg_file(i).data <= (others => '0');
                -- Only architectural registers (0-15) are ready initially
                if i < ARCH_REGS then
                    phys_reg_file(i).ready <= '1';
                    phys_reg_ready(i) <= '1';
                else
                    phys_reg_file(i).ready <= '0';
                    phys_reg_ready(i) <= '0';
                end if;
            end loop;

        elsif rising_edge(clk) then
            -- Mark destination registers as not ready when issued
            for i in 0 to ISSUE_WIDTH-1 loop
                if issue_valid(i) = '1' and issue_instr(i).dest_valid = '1' then
                    phys_reg_file(issue_instr(i).dest_phys_reg).ready <= '0';
                    phys_reg_ready(issue_instr(i).dest_phys_reg) <= '0';
                end if;
            end loop;

            -- Update register file from forwarding network
            for i in 0 to ISSUE_WIDTH-1 loop
                if forward_valid(i) = '1' then
                    phys_reg_file(forward_result(i).dest_phys_reg).data <= forward_result(i).result;
                    phys_reg_file(forward_result(i).dest_phys_reg).ready <= '1';
                    phys_reg_ready(forward_result(i).dest_phys_reg) <= '1';
                end if;
            end loop;

            -- Commit updates architectural state
            for i in 0 to ISSUE_WIDTH-1 loop
                if commit_valid(i) = '1' and commit_data(i).valid = '1' then
                    phys_reg_file(commit_data(i).phys_reg).data <= commit_data(i).data;
                    phys_reg_file(commit_data(i).phys_reg).valid <= '1';
                end if;
            end loop;
        end if;
    end process;

end architecture rtl;
