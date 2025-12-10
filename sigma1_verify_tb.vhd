-------------------------------------------------------------------------------
-- Verify small_sigma1 function in detail
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity sigma1_verify_tb is
end entity sigma1_verify_tb;

architecture sim of sigma1_verify_tb is

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
        variable x : word64;
        variable r19, r61, s6, result : word64;
    begin
        -- Test small_sigma1 with W[16] = 0x6162638000000000
        x := x"6162638000000000";

        r19 := rotr64(x, 19);
        r61 := rotr64(x, 61);
        s6 := shr64(x, 6);
        result := r19 xor r61 xor s6;

        report "x = " & word64_to_hex(x);
        report "ROTR^19(x) = " & word64_to_hex(r19);
        report "ROTR^61(x) = " & word64_to_hex(r61);
        report "SHR^6(x)   = " & word64_to_hex(s6);
        report "small_sigma1(x) = " & word64_to_hex(result);
        report "Via function: " & word64_to_hex(small_sigma1(x));

        -- Let me also compute what the values SHOULD be manually
        -- ROTR^19 shifts right 19, wrapping low 19 bits to high
        -- For x = 0x6162638000000000, low 19 bits are all 0
        -- So ROTR^19 should just be x >> 19
        -- 0x6162638000000000 >> 19 = 0x6162638000000000 / 2^19
        -- = 0x6162638000000000 / 524288 = 0xC2C4C70000

        wait;
    end process;

end architecture sim;
