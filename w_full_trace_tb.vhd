-------------------------------------------------------------------------------
-- Full W message schedule trace
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity w_full_trace_tb is
end entity w_full_trace_tb;

architecture sim of w_full_trace_tb is

    function to_hex_char(nibble : std_logic_vector(3 downto 0)) return character is
    begin
        case nibble is
            when "0000" => return '0'; when "0001" => return '1';
            when "0010" => return '2'; when "0011" => return '3';
            when "0100" => return '4'; when "0101" => return '5';
            when "0110" => return '6'; when "0111" => return '7';
            when "1000" => return '8'; when "1001" => return '9';
            when "1010" => return 'a'; when "1011" => return 'b';
            when "1100" => return 'c'; when "1101" => return 'd';
            when "1110" => return 'e'; when "1111" => return 'f';
            when others => return 'x';
        end case;
    end function;

    function word64_to_hex(w : std_logic_vector(63 downto 0)) return string is
        variable result : string(1 to 16);
    begin
        for i in 0 to 15 loop
            result(i+1) := to_hex_char(w(63-i*4 downto 60-i*4));
        end loop;
        return result;
    end function;

begin

    process
        type block_array is array (0 to 15) of word64;
        variable msg_block : block_array;
        variable W : word64_array(0 to 79);
    begin
        -- Test message: "abc" padded
        msg_block := (
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

        -- Message schedule
        for t in 0 to 15 loop
            W(t) := msg_block(t);
        end loop;

        for t in 16 to 79 loop
            W(t) := std_logic_vector(
                unsigned(small_sigma1(W(t-2))) +
                unsigned(W(t-7)) +
                unsigned(small_sigma0(W(t-15))) +
                unsigned(W(t-16))
            );
        end loop;

        -- Print all W values
        report "=== Full W message schedule ===";
        for t in 0 to 79 loop
            report "W[" & integer'image(t) & "] = " & word64_to_hex(W(t));
        end loop;

        wait;
    end process;

end architecture sim;
