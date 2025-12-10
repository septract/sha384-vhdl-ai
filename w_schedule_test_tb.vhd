-------------------------------------------------------------------------------
-- Message Schedule (W) Test - verify W expansion
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity w_schedule_test_tb is
end entity w_schedule_test_tb;

architecture sim of w_schedule_test_tb is

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
        variable x : word64;
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

        -- Initialize W[0..15]
        for t in 0 to 15 loop
            W(t) := msg_block(t);
        end loop;

        -- Test small_sigma functions
        report "=== Testing small_sigma functions ===";
        x := x"0000000000000018";
        report "small_sigma1(0x18):";
        report "  ROTR19 = " & word64_to_hex(rotr64(x, 19));
        report "  ROTR61 = " & word64_to_hex(rotr64(x, 61));
        report "  SHR6   = " & word64_to_hex(shr64(x, 6));
        report "  Result = " & word64_to_hex(small_sigma1(x));

        x := x"6162638000000000";
        report "small_sigma0(0x6162638000000000):";
        report "  ROTR1  = " & word64_to_hex(rotr64(x, 1));
        report "  ROTR8  = " & word64_to_hex(rotr64(x, 8));
        report "  SHR7   = " & word64_to_hex(shr64(x, 7));
        report "  Result = " & word64_to_hex(small_sigma0(x));

        -- Compute W[16..20]
        report "=== Computing W[16..20] ===";
        for t in 16 to 20 loop
            W(t) := std_logic_vector(
                unsigned(small_sigma1(W(t-2))) +
                unsigned(W(t-7)) +
                unsigned(small_sigma0(W(t-15))) +
                unsigned(W(t-16))
            );
            report "W[" & integer'image(t) & "] = " & word64_to_hex(W(t));
            report "  sigma1(W[" & integer'image(t-2) & "]) = " & word64_to_hex(small_sigma1(W(t-2)));
            report "  W[" & integer'image(t-7) & "] = " & word64_to_hex(W(t-7));
            report "  sigma0(W[" & integer'image(t-15) & "]) = " & word64_to_hex(small_sigma0(W(t-15)));
            report "  W[" & integer'image(t-16) & "] = " & word64_to_hex(W(t-16));
        end loop;

        wait;
    end process;

end architecture sim;
