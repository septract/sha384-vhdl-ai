-------------------------------------------------------------------------------
-- Verify K constants
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity k_verify_tb is
end entity k_verify_tb;

architecture sim of k_verify_tb is

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

    -- First 20 K constants from FIPS 180-4
    type expected_k_type is array (0 to 19) of std_logic_vector(63 downto 0);
    constant EXPECTED_K : expected_k_type := (
        x"428a2f98d728ae22", x"7137449123ef65cd", x"b5c0fbcfec4d3b2f", x"e9b5dba58189dbbc",
        x"3956c25bf348b538", x"59f111f1b605d019", x"923f82a4af194f9b", x"ab1c5ed5da6d8118",
        x"d807aa98a3030242", x"12835b0145706fbe", x"243185be4ee4b28c", x"550c7dc3d5ffb4e2",
        x"72be5d74f27b896f", x"80deb1fe3b1696b1", x"9bdc06a725c71235", x"c19bf174cf692694",
        x"e49b69c19ef14ad2", x"efbe4786384f25e3", x"0fc19dc68b8cd5b5", x"240ca1cc77ac9c65"
    );

begin

    process
        variable mismatch : boolean := false;
    begin
        report "Verifying K constants (first 20):";

        for i in 0 to 19 loop
            if K(i) /= EXPECTED_K(i) then
                report "MISMATCH at K[" & integer'image(i) & "]:";
                report "  Got:      " & word64_to_hex(K(i));
                report "  Expected: " & word64_to_hex(EXPECTED_K(i));
                mismatch := true;
            end if;
        end loop;

        if not mismatch then
            report "All K[0..19] constants match!";
        end if;

        -- Also verify last few K constants
        report "K[78] = " & word64_to_hex(K(78));
        report "K[79] = " & word64_to_hex(K(79));
        report "Expected K[78] = 5fcb6fab3ad6faec";
        report "Expected K[79] = 6c44198c4a475817";

        wait;
    end process;

end architecture sim;
