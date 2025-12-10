-------------------------------------------------------------------------------
-- SHA-384 Debug Testbench - prints actual hash output
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity sha384_debug_tb is
end entity sha384_debug_tb;

architecture sim of sha384_debug_tb is

    constant CLK_PERIOD : time := 10 ns;

    signal clk        : std_logic := '0';
    signal reset      : std_logic := '1';
    signal start      : std_logic := '0';
    signal data_in    : std_logic_vector(63 downto 0) := (others => '0');
    signal data_valid : std_logic := '0';
    signal last_block : std_logic := '0';
    signal ready      : std_logic;
    signal hash_out   : std_logic_vector(383 downto 0);
    signal hash_valid : std_logic;

    signal test_done  : boolean := false;

    -- Convert nibble to hex character
    function to_hex_char(nibble : std_logic_vector(3 downto 0)) return character is
    begin
        case nibble is
            when "0000" => return '0';
            when "0001" => return '1';
            when "0010" => return '2';
            when "0011" => return '3';
            when "0100" => return '4';
            when "0101" => return '5';
            when "0110" => return '6';
            when "0111" => return '7';
            when "1000" => return '8';
            when "1001" => return '9';
            when "1010" => return 'a';
            when "1011" => return 'b';
            when "1100" => return 'c';
            when "1101" => return 'd';
            when "1110" => return 'e';
            when "1111" => return 'f';
            when others => return 'x';
        end case;
    end function;

    -- Convert 64-bit word to hex string
    function word64_to_hex(w : std_logic_vector(63 downto 0)) return string is
        variable result : string(1 to 16);
    begin
        for i in 0 to 15 loop
            result(i+1) := to_hex_char(w(63-i*4 downto 60-i*4));
        end loop;
        return result;
    end function;

begin

    dut: entity work.sha384
        port map (
            clk        => clk,
            reset      => reset,
            start      => start,
            data_in    => data_in,
            data_valid => data_valid,
            last_block => last_block,
            ready      => ready,
            hash_out   => hash_out,
            hash_valid => hash_valid
        );

    clk_proc: process
    begin
        while not test_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    stim_proc: process
        -- Test vector 1: "abc" (padded to 1024 bits)
        type block_array is array (0 to 15) of std_logic_vector(63 downto 0);
        constant tv1_block : block_array := (
            x"6162638000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000018"
        );
    begin
        reset <= '1';
        wait for CLK_PERIOD * 5;
        reset <= '0';
        wait for CLK_PERIOD * 2;

        report "Testing SHA-384 with 'abc'";
        report "Expected: cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7";

        wait until rising_edge(clk) and ready = '1';
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        -- Send block
        for i in 0 to 15 loop
            wait until rising_edge(clk) and ready = '1';
            data_in <= tv1_block(i);
            data_valid <= '1';
            if i = 15 then
                last_block <= '1';
            end if;
            wait until rising_edge(clk);
            data_valid <= '0';
            last_block <= '0';
        end loop;

        wait until rising_edge(clk) and hash_valid = '1';
        wait for 1 ns;

        report "Computed hash:";
        report "  H0: " & word64_to_hex(hash_out(383 downto 320));
        report "  H1: " & word64_to_hex(hash_out(319 downto 256));
        report "  H2: " & word64_to_hex(hash_out(255 downto 192));
        report "  H3: " & word64_to_hex(hash_out(191 downto 128));
        report "  H4: " & word64_to_hex(hash_out(127 downto 64));
        report "  H5: " & word64_to_hex(hash_out(63 downto 0));

        test_done <= true;
        wait;
    end process;

end architecture sim;
