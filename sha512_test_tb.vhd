-------------------------------------------------------------------------------
-- SHA-512 Test - verify algorithm with SHA-512 initial values
-- Expected SHA-512("abc") = ddaf35a193617aba cc417349ae204131
--                           12e6fa4e89a97ea2 0a9eeee64b55d39a
--                           2192992a274fc1a8 36ba3c23a3feebbd
--                           454d4423643ce80e 2a9ac94fa54ca49f
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity sha512_test_tb is
end entity sha512_test_tb;

architecture sim of sha512_test_tb is

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

    -- SHA-512 initial hash values (different from SHA-384)
    constant SHA512_H0 : word64 := x"6a09e667f3bcc908";
    constant SHA512_H1 : word64 := x"bb67ae8584caa73b";
    constant SHA512_H2 : word64 := x"3c6ef372fe94f82b";
    constant SHA512_H3 : word64 := x"a54ff53a5f1d36f1";
    constant SHA512_H4 : word64 := x"510e527fade682d1";
    constant SHA512_H5 : word64 := x"9b05688c2b3e6c1f";
    constant SHA512_H6 : word64 := x"1f83d9abfb41bd6b";
    constant SHA512_H7 : word64 := x"5be0cd19137e2179";

begin

    process
        type block_array is array (0 to 15) of word64;
        variable msg_block : block_array;
        variable W : word64_array(0 to 79);
        variable a, b, c, d, e, f, g, h : word64;
        variable T1, T2 : word64;
        variable H0, H1, H2, H3, H4, H5, H6, H7 : word64;
    begin
        -- Test message: "abc" padded to 1024 bits
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

        -- Initialize with SHA-512 values
        H0 := SHA512_H0;
        H1 := SHA512_H1;
        H2 := SHA512_H2;
        H3 := SHA512_H3;
        H4 := SHA512_H4;
        H5 := SHA512_H5;
        H6 := SHA512_H6;
        H7 := SHA512_H7;

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

        -- Initialize working variables
        a := H0; b := H1; c := H2; d := H3;
        e := H4; f := H5; g := H6; h := H7;

        -- 80 rounds
        for t in 0 to 79 loop
            T1 := std_logic_vector(
                unsigned(h) +
                unsigned(big_sigma1(e)) +
                unsigned(ch(e, f, g)) +
                unsigned(K(t)) +
                unsigned(W(t))
            );
            T2 := std_logic_vector(
                unsigned(big_sigma0(a)) +
                unsigned(maj(a, b, c))
            );
            h := g; g := f; f := e;
            e := std_logic_vector(unsigned(d) + unsigned(T1));
            d := c; c := b; b := a;
            a := std_logic_vector(unsigned(T1) + unsigned(T2));
        end loop;

        -- Update hash
        H0 := std_logic_vector(unsigned(SHA512_H0) + unsigned(a));
        H1 := std_logic_vector(unsigned(SHA512_H1) + unsigned(b));
        H2 := std_logic_vector(unsigned(SHA512_H2) + unsigned(c));
        H3 := std_logic_vector(unsigned(SHA512_H3) + unsigned(d));
        H4 := std_logic_vector(unsigned(SHA512_H4) + unsigned(e));
        H5 := std_logic_vector(unsigned(SHA512_H5) + unsigned(f));
        H6 := std_logic_vector(unsigned(SHA512_H6) + unsigned(g));
        H7 := std_logic_vector(unsigned(SHA512_H7) + unsigned(h));

        report "=== SHA-512(abc) Test ===";
        report "Computed:";
        report "  H0: " & word64_to_hex(H0);
        report "  H1: " & word64_to_hex(H1);
        report "  H2: " & word64_to_hex(H2);
        report "  H3: " & word64_to_hex(H3);
        report "  H4: " & word64_to_hex(H4);
        report "  H5: " & word64_to_hex(H5);
        report "  H6: " & word64_to_hex(H6);
        report "  H7: " & word64_to_hex(H7);
        report "Expected:";
        report "  H0: ddaf35a193617aba";
        report "  H1: cc417349ae204131";
        report "  H2: 12e6fa4e89a97ea2";
        report "  H3: 0a9eeee64b55d39a";
        report "  H4: 2192992a274fc1a8";
        report "  H5: 36ba3c23a3feebbd";
        report "  H6: 454d4423643ce80e";
        report "  H7: 2a9ac94fa54ca49f";

        wait;
    end process;

end architecture sim;
