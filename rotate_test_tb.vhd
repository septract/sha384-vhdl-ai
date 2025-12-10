-------------------------------------------------------------------------------
-- Test rotate_right behavior
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rotate_test_tb is
end entity rotate_test_tb;

architecture sim of rotate_test_tb is

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
        variable x : std_logic_vector(63 downto 0);
        variable r : std_logic_vector(63 downto 0);
    begin
        -- Test value: 0x8000000000000000 (just MSB set)
        x := x"8000000000000000";
        report "x = " & word64_to_hex(x);

        -- Rotate right by 1: should move MSB to bit 62
        r := std_logic_vector(rotate_right(unsigned(x), 1));
        report "ROTR(x, 1) = " & word64_to_hex(r);
        report "Expected:    4000000000000000";

        -- Rotate right by 4: should move MSB to bit 59
        r := std_logic_vector(rotate_right(unsigned(x), 4));
        report "ROTR(x, 4) = " & word64_to_hex(r);
        report "Expected:    0800000000000000";

        -- Test with a known value
        -- 0xfedcba9876543210 rotated right by 8 should give 0x10fedcba98765432
        x := x"fedcba9876543210";
        r := std_logic_vector(rotate_right(unsigned(x), 8));
        report "ROTR(0xfedcba9876543210, 8) = " & word64_to_hex(r);
        report "Expected:                      10fedcba98765432";

        -- Shift right by 8 should give 0x00fedcba98765432
        r := std_logic_vector(shift_right(unsigned(x), 8));
        report "SHR(0xfedcba9876543210, 8) = " & word64_to_hex(r);
        report "Expected:                     00fedcba98765432";

        wait;
    end process;

end architecture sim;
