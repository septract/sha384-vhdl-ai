-------------------------------------------------------------------------------
-- SHA-384 Function Test - verify individual functions
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity sha384_func_test_tb is
end entity sha384_func_test_tb;

architecture sim of sha384_func_test_tb is

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
        variable x, y, z : word64;
        variable result : word64;
        variable W0 : word64;
        variable T1, T2 : word64;
    begin
        report "=== Testing SHA-384 Functions ===";

        -- Test with H4 = 67332667ffc00b31
        x := x"67332667ffc00b31";

        report "Testing BSIG1(0x67332667ffc00b31):";
        report "  ROTR14 = " & word64_to_hex(rotr64(x, 14));
        report "  ROTR18 = " & word64_to_hex(rotr64(x, 18));
        report "  ROTR41 = " & word64_to_hex(rotr64(x, 41));
        result := big_sigma1(x);
        report "  BSIG1  = " & word64_to_hex(result);

        -- Test Ch function with H4, H5, H6
        x := x"67332667ffc00b31";  -- H4
        y := x"8eb44a8768581511";  -- H5
        z := x"db0c2e0d64f98fa7";  -- H6
        result := ch(x, y, z);
        report "Testing Ch(H4, H5, H6):";
        report "  Ch = " & word64_to_hex(result);

        -- Test BSIG0 with H0
        x := x"cbbb9d5dc1059ed8";  -- H0
        result := big_sigma0(x);
        report "Testing BSIG0(H0):";
        report "  BSIG0 = " & word64_to_hex(result);

        -- Test Maj with H0, H1, H2
        x := x"cbbb9d5dc1059ed8";  -- H0
        y := x"629a292a367cd507";  -- H1
        z := x"9159015a3070dd17";  -- H2
        result := maj(x, y, z);
        report "Testing Maj(H0, H1, H2):";
        report "  Maj = " & word64_to_hex(result);

        -- Now compute T1 for round 0
        report "=== Computing T1 for round 0 ===";
        report "h (H7) = " & word64_to_hex(H7_INIT);
        report "BSIG1(e) = " & word64_to_hex(big_sigma1(x"67332667ffc00b31"));
        report "Ch(e,f,g) = " & word64_to_hex(ch(x"67332667ffc00b31", x"8eb44a8768581511", x"db0c2e0d64f98fa7"));
        report "K[0] = " & word64_to_hex(K(0));
        report "W[0] = 6162638000000000";

        -- T1 = h + BSIG1(e) + Ch(e,f,g) + K[0] + W[0]
        W0 := x"6162638000000000";
        T1 := std_logic_vector(
            unsigned(H7_INIT) +
            unsigned(big_sigma1(x"67332667ffc00b31")) +
            unsigned(ch(x"67332667ffc00b31", x"8eb44a8768581511", x"db0c2e0d64f98fa7")) +
            unsigned(K(0)) +
            unsigned(W0)
        );
        report "T1 = " & word64_to_hex(T1);

        -- T2 = BSIG0(a) + Maj(a,b,c)
        T2 := std_logic_vector(
            unsigned(big_sigma0(x"cbbb9d5dc1059ed8")) +
            unsigned(maj(x"cbbb9d5dc1059ed8", x"629a292a367cd507", x"9159015a3070dd17"))
        );
        report "T2 = " & word64_to_hex(T2);

        -- new_a = T1 + T2
        report "new_a (T1+T2) = " & word64_to_hex(std_logic_vector(unsigned(T1) + unsigned(T2)));

        -- new_e = d + T1 = H3 + T1
        result := std_logic_vector(unsigned(H3_INIT) + unsigned(T1));
        report "new_e (H3+T1) = " & word64_to_hex(result);

        wait;
    end process;

end architecture sim;
