------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K Performance Counters                                              --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Hardware performance counters for profiling and analysis                --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_PerfCounters is
    port(
        clk             : in std_logic;
        reset           : in std_logic;
        enable          : in std_logic;

        -- Event inputs
        fetch_valid     : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        decode_valid    : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        dispatch_valid  : in std_logic_vector(ISSUE_WIDTH-1 downto 0);
        issue_valid     : in std_logic_vector(EU_COUNT-1 downto 0);
        commit_valid    : in std_logic_vector(ISSUE_WIDTH-1 downto 0);

        fetch_stall     : in std_logic;
        decode_stall    : in std_logic;
        rob_full        : in std_logic;
        rs_full         : in std_logic;

        branch_mispredict : in std_logic;
        flush_pipeline    : in std_logic;

        -- Counter outputs
        cycles          : out std_logic_vector(63 downto 0);
        instructions_fetched : out std_logic_vector(63 downto 0);
        instructions_decoded : out std_logic_vector(63 downto 0);
        instructions_dispatched : out std_logic_vector(63 downto 0);
        instructions_issued : out std_logic_vector(63 downto 0);
        instructions_committed : out std_logic_vector(63 downto 0);

        stall_cycles_fetch : out std_logic_vector(63 downto 0);
        stall_cycles_rob : out std_logic_vector(63 downto 0);
        stall_cycles_rs : out std_logic_vector(63 downto 0);

        branch_mispredicts : out std_logic_vector(63 downto 0);
        pipeline_flushes : out std_logic_vector(63 downto 0);

        -- IPC (calculated)
        ipc_integer     : out std_logic_vector(7 downto 0);  -- Integer part
        ipc_fraction    : out std_logic_vector(7 downto 0)   -- Fractional part (x/256)
    );
end TG68K_PerfCounters;

architecture rtl of TG68K_PerfCounters is

    signal cycle_count : unsigned(63 downto 0);
    signal fetch_count : unsigned(63 downto 0);
    signal decode_count : unsigned(63 downto 0);
    signal dispatch_count : unsigned(63 downto 0);
    signal issue_count : unsigned(63 downto 0);
    signal commit_count : unsigned(63 downto 0);

    signal stall_fetch_count : unsigned(63 downto 0);
    signal stall_rob_count : unsigned(63 downto 0);
    signal stall_rs_count : unsigned(63 downto 0);

    signal branch_mispredict_count : unsigned(63 downto 0);
    signal flush_count : unsigned(63 downto 0);

    -- Helper function to count set bits
    function count_ones(vec : std_logic_vector) return integer is
        variable count : integer := 0;
    begin
        for i in vec'range loop
            if vec(i) = '1' then
                count := count + 1;
            end if;
        end loop;
        return count;
    end function;

begin

    -- Output assignments
    cycles <= std_logic_vector(cycle_count);
    instructions_fetched <= std_logic_vector(fetch_count);
    instructions_decoded <= std_logic_vector(decode_count);
    instructions_dispatched <= std_logic_vector(dispatch_count);
    instructions_issued <= std_logic_vector(issue_count);
    instructions_committed <= std_logic_vector(commit_count);

    stall_cycles_fetch <= std_logic_vector(stall_fetch_count);
    stall_cycles_rob <= std_logic_vector(stall_rob_count);
    stall_cycles_rs <= std_logic_vector(stall_rs_count);

    branch_mispredicts <= std_logic_vector(branch_mispredict_count);
    pipeline_flushes <= std_logic_vector(flush_count);

    -- Main counting process
    process(clk, reset)
        variable fetch_this_cycle : integer;
        variable decode_this_cycle : integer;
        variable dispatch_this_cycle : integer;
        variable issue_this_cycle : integer;
        variable commit_this_cycle : integer;
    begin
        if reset = '1' then
            cycle_count <= (others => '0');
            fetch_count <= (others => '0');
            decode_count <= (others => '0');
            dispatch_count <= (others => '0');
            issue_count <= (others => '0');
            commit_count <= (others => '0');
            stall_fetch_count <= (others => '0');
            stall_rob_count <= (others => '0');
            stall_rs_count <= (others => '0');
            branch_mispredict_count <= (others => '0');
            flush_count <= (others => '0');

        elsif rising_edge(clk) then
            if enable = '1' then

                -- Count cycles
                cycle_count <= cycle_count + 1;

                -- Count instructions at each stage
                fetch_this_cycle := count_ones(fetch_valid);
                decode_this_cycle := count_ones(decode_valid);
                dispatch_this_cycle := count_ones(dispatch_valid);
                issue_this_cycle := count_ones(issue_valid);
                commit_this_cycle := count_ones(commit_valid);

                fetch_count <= fetch_count + to_unsigned(fetch_this_cycle, 64);
                decode_count <= decode_count + to_unsigned(decode_this_cycle, 64);
                dispatch_count <= dispatch_count + to_unsigned(dispatch_this_cycle, 64);
                issue_count <= issue_count + to_unsigned(issue_this_cycle, 64);
                commit_count <= commit_count + to_unsigned(commit_this_cycle, 64);

                -- Count stall cycles
                if fetch_stall = '1' then
                    stall_fetch_count <= stall_fetch_count + 1;
                end if;

                if rob_full = '1' then
                    stall_rob_count <= stall_rob_count + 1;
                end if;

                if rs_full = '1' then
                    stall_rs_count <= stall_rs_count + 1;
                end if;

                -- Count events
                if branch_mispredict = '1' then
                    branch_mispredict_count <= branch_mispredict_count + 1;
                end if;

                if flush_pipeline = '1' then
                    flush_count <= flush_count + 1;
                end if;

            end if;
        end if;
    end process;

    -- Calculate IPC (Instructions Per Cycle)
    process(cycle_count, commit_count)
        variable ipc_calc : unsigned(71 downto 0);  -- 64-bit * 256 for precision
    begin
        if cycle_count > 0 then
            -- IPC = (committed * 256) / cycles
            ipc_calc := shift_left(commit_count, 8) / cycle_count;

            ipc_integer <= std_logic_vector(ipc_calc(15 downto 8));
            ipc_fraction <= std_logic_vector(ipc_calc(7 downto 0));
        else
            ipc_integer <= (others => '0');
            ipc_fraction <= (others => '0');
        end if;
    end process;

end rtl;
