-------------------------------------------------------------------------------
-- Arithmetic Test - verify 64-bit addition with wrap-around
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arith_test_tb is
end entity arith_test_tb;

architecture sim of arith_test_tb is

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
        variable a, b, c : std_logic_vector(63 downto 0);
        variable h_val, bsig1, ch_val, k_val, w_val : std_logic_vector(63 downto 0);
    begin
        -- Test 1: Simple addition
        a := x"0000000000000001";
        b := x"0000000000000002";
        c := std_logic_vector(unsigned(a) + unsigned(b));
        report "1 + 2 = " & word64_to_hex(c);
        report "Expected: 0000000000000003";

        -- Test 2: Addition with overflow
        a := x"ffffffffffffffff";
        b := x"0000000000000001";
        c := std_logic_vector(unsigned(a) + unsigned(b));
        report "0xFFFF...FFFF + 1 = " & word64_to_hex(c);
        report "Expected: 0000000000000000 (wrap around)";

        -- Test 3: Large values from SHA computation
        a := x"47b5481dbefa4fa4";  -- H7
        b := x"428a2f98d728ae22";  -- K[0]
        c := std_logic_vector(unsigned(a) + unsigned(b));
        report "H7 + K[0] = " & word64_to_hex(c);

        -- Test 4: Five-term addition like T1
        h_val := x"47b5481dbefa4fa4";
        bsig1 := x"1df62505c8b59963";
        ch_val:= x"9e3c0a0f68798597";
        k_val := x"428a2f98d728ae22";
        w_val := x"6162638000000000";
        a := std_logic_vector(
            unsigned(h_val) +
            unsigned(bsig1) +
            unsigned(ch_val) +
            unsigned(k_val) +
            unsigned(w_val)
        );
        report "Five-term T1 sum = " & word64_to_hex(a);
        report "This should match T1 from func test: a7d40a4bc7521cc0";

        wait;
    end process;

end architecture sim;
