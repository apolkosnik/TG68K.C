------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K Load/Store Queue (LSQ)                                            --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- Handles load/store operations with memory disambiguation                --
-- Detects and resolves memory dependencies                                --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_LoadStoreQueue is
    generic(
        LSQ_SIZE : integer := 16  -- Number of LSQ entries
    );
    port(
        clk             : in std_logic;
        reset           : in std_logic;
        enable          : in std_logic;

        -- Dispatch interface
        dispatch_valid  : in std_logic;
        dispatch_is_load : in std_logic;
        dispatch_is_store : in std_logic;
        dispatch_addr   : in std_logic_vector(31 downto 0);
        dispatch_data   : in std_logic_vector(31 downto 0);  -- For stores
        dispatch_size   : in std_logic_vector(1 downto 0);   -- 00=byte, 01=word, 10=long
        dispatch_rob_idx : in integer range 0 to ROB_SIZE-1;

        lsq_full        : out std_logic;

        -- Memory interface
        mem_addr        : out std_logic_vector(31 downto 0);
        mem_write       : out std_logic;
        mem_read        : out std_logic;
        mem_data_out    : out std_logic_vector(31 downto 0);
        mem_data_in     : in std_logic_vector(31 downto 0);
        mem_ready       : in std_logic;
        mem_size        : out std_logic_vector(1 downto 0);

        -- Completion interface
        complete_valid  : out std_logic;
        complete_rob_idx : out integer range 0 to ROB_SIZE-1;
        complete_data   : out std_logic_vector(31 downto 0);

        -- Commit interface (from ROB - allows stores to commit)
        commit_rob_idx  : in integer range 0 to ROB_SIZE-1;
        commit_valid    : in std_logic;

        -- Flush on misprediction
        flush           : in std_logic
    );
end TG68K_LoadStoreQueue;

architecture rtl of TG68K_LoadStoreQueue is

    type lsq_entry_t is record
        valid      : std_logic;
        is_load    : std_logic;
        is_store   : std_logic;
        addr       : std_logic_vector(31 downto 0);
        data       : std_logic_vector(31 downto 0);
        size       : std_logic_vector(1 downto 0);
        rob_idx    : integer range 0 to ROB_SIZE-1;
        addr_valid : std_logic;  -- Address computed
        executed   : std_logic;  -- Memory access complete
        committed  : std_logic;  -- Store committed by ROB
    end record;

    type lsq_t is array (0 to LSQ_SIZE-1) of lsq_entry_t;
    signal lsq : lsq_t;

    signal head_ptr : integer range 0 to LSQ_SIZE-1;
    signal tail_ptr : integer range 0 to LSQ_SIZE-1;
    signal entry_count : integer range 0 to LSQ_SIZE;

    signal is_full : std_logic;
    signal mem_busy : std_logic;

    -- Function to check if addresses conflict (for memory disambiguation)
    function addr_conflict(addr1, addr2 : std_logic_vector(31 downto 0);
                          size1, size2 : std_logic_vector(1 downto 0)) return boolean is
        variable end1, end2 : unsigned(31 downto 0);
        variable bytes1, bytes2 : integer;
    begin
        -- Determine size in bytes
        case size1 is
            when "00" => bytes1 := 1;  -- Byte
            when "01" => bytes1 := 2;  -- Word
            when "10" => bytes2 := 4;  -- Long
            when others => bytes1 := 1;
        end case;

        case size2 is
            when "00" => bytes2 := 1;
            when "01" => bytes2 := 2;
            when "10" => bytes2 := 4;
            when others => bytes2 := 1;
        end case;

        end1 := unsigned(addr1) + to_unsigned(bytes1 - 1, 32);
        end2 := unsigned(addr2) + to_unsigned(bytes2 - 1, 32);

        -- Check for overlap
        if (unsigned(addr1) <= unsigned(addr2) and end1 >= unsigned(addr2)) or
           (unsigned(addr2) <= unsigned(addr1) and end2 >= unsigned(addr1)) then
            return true;
        else
            return false;
        end if;
    end function;

begin

    lsq_full <= is_full;

    -- Check if LSQ is full
    process(entry_count)
    begin
        if entry_count >= LSQ_SIZE - 2 then
            is_full <= '1';
        else
            is_full <= '0';
        end if;
    end process;

    -- Main LSQ logic
    process(clk, reset)
        variable can_issue : std_logic;
        variable older_store_conflict : boolean;
    begin
        if reset = '1' then
            for i in 0 to LSQ_SIZE-1 loop
                lsq(i).valid <= '0';
                lsq(i).executed <= '0';
                lsq(i).committed <= '0';
            end loop;

            head_ptr <= 0;
            tail_ptr <= 0;
            entry_count <= 0;
            mem_write <= '0';
            mem_read <= '0';
            mem_busy <= '0';
            complete_valid <= '0';

        elsif rising_edge(clk) then
            if enable = '1' then

                complete_valid <= '0';
                mem_write <= '0';
                mem_read <= '0';

                -- Handle flush
                if flush = '1' then
                    for i in 0 to LSQ_SIZE-1 loop
                        if lsq(i).is_store = '0' or lsq(i).committed = '0' then
                            lsq(i).valid <= '0';
                        end if;
                    end loop;
                    -- Recalculate entry_count after flush
                else

                    -- ========================================
                    -- DISPATCH: Add new load/store to LSQ
                    -- ========================================
                    if dispatch_valid = '1' and is_full = '0' then
                        lsq(tail_ptr).valid <= '1';
                        lsq(tail_ptr).is_load <= dispatch_is_load;
                        lsq(tail_ptr).is_store <= dispatch_is_store;
                        lsq(tail_ptr).addr <= dispatch_addr;
                        lsq(tail_ptr).data <= dispatch_data;
                        lsq(tail_ptr).size <= dispatch_size;
                        lsq(tail_ptr).rob_idx <= dispatch_rob_idx;
                        lsq(tail_ptr).addr_valid <= '1';  -- Assume address is ready
                        lsq(tail_ptr).executed <= '0';
                        lsq(tail_ptr).committed <= '0';

                        if tail_ptr = LSQ_SIZE-1 then
                            tail_ptr <= 0;
                        else
                            tail_ptr <= tail_ptr + 1;
                        end if;

                        entry_count <= entry_count + 1;
                    end if;

                    -- ========================================
                    -- COMMIT: Mark stores as committed
                    -- ========================================
                    if commit_valid = '1' then
                        for i in 0 to LSQ_SIZE-1 loop
                            if lsq(i).valid = '1' and lsq(i).rob_idx = commit_rob_idx then
                                lsq(i).committed <= '1';
                            end if;
                        end loop;
                    end if;

                    -- ========================================
                    -- ISSUE: Execute load/store
                    -- ========================================
                    if mem_busy = '0' then
                        -- Find oldest ready entry to execute
                        for i in 0 to LSQ_SIZE-1 loop
                            if lsq(i).valid = '1' and lsq(i).addr_valid = '1' and lsq(i).executed = '0' then

                                can_issue := '1';

                                -- For loads: check for older conflicting stores
                                if lsq(i).is_load = '1' then
                                    older_store_conflict := false;

                                    -- Check all older stores
                                    for j in 0 to LSQ_SIZE-1 loop
                                        if lsq(j).valid = '1' and lsq(j).is_store = '1' and
                                           lsq(j).executed = '0' then
                                            if addr_conflict(lsq(i).addr, lsq(j).addr,
                                                           lsq(i).size, lsq(j).size) then
                                                older_store_conflict := true;
                                            end if;
                                        end if;
                                    end loop;

                                    if older_store_conflict then
                                        can_issue := '0';
                                    end if;
                                end if;

                                -- For stores: must be committed
                                if lsq(i).is_store = '1' and lsq(i).committed = '0' then
                                    can_issue := '0';
                                end if;

                                -- Issue if ready
                                if can_issue = '1' then
                                    mem_addr <= lsq(i).addr;
                                    mem_size <= lsq(i).size;

                                    if lsq(i).is_load = '1' then
                                        mem_read <= '1';
                                        mem_write <= '0';
                                    else
                                        mem_read <= '0';
                                        mem_write <= '1';
                                        mem_data_out <= lsq(i).data;
                                    end if;

                                    mem_busy <= '1';
                                    exit;  -- Issue one at a time
                                end if;
                            end if;
                        end loop;
                    end if;

                    -- ========================================
                    -- COMPLETE: Handle memory response
                    -- ========================================
                    if mem_busy = '1' and mem_ready = '1' then
                        for i in 0 to LSQ_SIZE-1 loop
                            if lsq(i).valid = '1' and lsq(i).addr = mem_addr and
                               lsq(i).executed = '0' then

                                lsq(i).executed <= '1';
                                complete_valid <= '1';
                                complete_rob_idx <= lsq(i).rob_idx;

                                if lsq(i).is_load = '1' then
                                    complete_data <= mem_data_in;
                                else
                                    complete_data <= (others => '0');
                                end if;

                                exit;
                            end if;
                        end loop;

                        mem_busy <= '0';
                    end if;

                    -- ========================================
                    -- RETIRE: Remove completed entries from head
                    -- ========================================
                    if lsq(head_ptr).valid = '1' and lsq(head_ptr).executed = '1' then
                        if lsq(head_ptr).is_load = '1' or
                           (lsq(head_ptr).is_store = '1' and lsq(head_ptr).committed = '1') then

                            lsq(head_ptr).valid <= '0';

                            if head_ptr = LSQ_SIZE-1 then
                                head_ptr <= 0;
                            else
                                head_ptr <= head_ptr + 1;
                            end if;

                            entry_count <= entry_count - 1;
                        end if;
                    end if;

                end if;  -- not flush
            end if;  -- enable
        end if;  -- clk
    end process;

end rtl;
