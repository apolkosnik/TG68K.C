------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- TG68K SuperScalar Physical Register File                                --
-- Copyright (c) 2025 Tobias Gubener <tobiflex@opencores.org>              --
--                                                                          --
-- 64 physical registers for register renaming                             --
-- Multi-ported: 8 read ports, 4 write ports                               --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.TG68K_Pack.all;
use work.TG68K_SuperScalar_Pack.all;

entity TG68K_PhysicalRegFile is
    port(
        clk             : in std_logic;
        reset           : in std_logic;
        enable          : in std_logic;

        -- Read ports (8 ports for 4 instructions * 2 sources)
        read_addr       : in prf_read_array_t;
        read_data       : out prf_rdata_array_t;

        -- Write ports (4 ports for commit stage)
        write_enable    : in std_logic_vector(3 downto 0);
        write_addr      : in prf_write_array_t;
        write_data      : in prf_wdata_array_t;

        -- Broadcast ports (4 ports for execution unit results - forwarding)
        broadcast_enable: in std_logic_vector(EU_COUNT-1 downto 0);
        broadcast_addr  : in eu_preg_array_t;
        broadcast_data  : in eu_data_array_t
    );
end TG68K_PhysicalRegFile;

architecture rtl of TG68K_PhysicalRegFile is

    signal regfile : phys_regfile_t;

begin

    -- Asynchronous read (combinational)
    process(regfile, read_addr, broadcast_enable, broadcast_addr, broadcast_data)
    begin
        for i in 0 to 7 loop
            read_data(i) <= regfile(to_integer(unsigned(read_addr(i))));

            -- Forwarding from broadcast (if available)
            for j in 0 to EU_COUNT-1 loop
                if broadcast_enable(j) = '1' and broadcast_addr(j) = read_addr(i) then
                    read_data(i) <= broadcast_data(j);
                end if;
            end loop;
        end loop;
    end process;

    -- Synchronous write
    process(clk, reset)
    begin
        if reset = '1' then
            regfile <= (others => (others => '0'));

        elsif rising_edge(clk) then
            if enable = '1' then

                -- Write from commit stage
                for i in 0 to 3 loop
                    if write_enable(i) = '1' then
                        regfile(to_integer(unsigned(write_addr(i)))) <= write_data(i);
                    end if;
                end loop;

                -- Broadcast from execution units (for forwarding)
                for i in 0 to EU_COUNT-1 loop
                    if broadcast_enable(i) = '1' then
                        regfile(to_integer(unsigned(broadcast_addr(i)))) <= broadcast_data(i);
                    end if;
                end loop;

            end if;
        end if;
    end process;

end rtl;
