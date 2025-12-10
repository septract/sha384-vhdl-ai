-------------------------------------------------------------------------------
-- SHA-384 Reference Testbench
-- Computes SHA-384 using only variables (no signal timing issues)
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity sha384_ref_tb is
end entity sha384_ref_tb;

architecture sim of sha384_ref_tb is

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

        -- Working variables
        variable W : word64_array(0 to 79);
        variable a, b, c, d, e, f, g, h : word64;
        variable T1, T2 : word64;
        variable H0, H1, H2, H3, H4, H5, H6, H7 : word64;

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

        -- Initialize hash values
        H0 := H0_INIT;
        H1 := H1_INIT;
        H2 := H2_INIT;
        H3 := H3_INIT;
        H4 := H4_INIT;
        H5 := H5_INIT;
        H6 := H6_INIT;
        H7 := H7_INIT;

        report "Initial hash values:";
        report "H0=" & word64_to_hex(H0);
        report "H7=" & word64_to_hex(H7);

        -- Message schedule: first 16 words from message
        for t in 0 to 15 loop
            W(t) := msg_block(t);
        end loop;

        -- Message schedule: words 16-79
        for t in 16 to 79 loop
            W(t) := std_logic_vector(
                unsigned(small_sigma1(W(t-2))) +
                unsigned(W(t-7)) +
                unsigned(small_sigma0(W(t-15))) +
                unsigned(W(t-16))
            );
        end loop;

        report "W[0]=" & word64_to_hex(W(0));
        report "W[1]=" & word64_to_hex(W(1));
        report "W[16]=" & word64_to_hex(W(16));

        -- Initialize working variables
        a := H0;
        b := H1;
        c := H2;
        d := H3;
        e := H4;
        f := H5;
        g := H6;
        h := H7;

        -- Compression: 80 rounds
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

            h := g;
            g := f;
            f := e;
            e := std_logic_vector(unsigned(d) + unsigned(T1));
            d := c;
            c := b;
            b := a;
            a := std_logic_vector(unsigned(T1) + unsigned(T2));

            if t < 3 then
                report "After round " & integer'image(t) & ":";
                report "  a=" & word64_to_hex(a);
                report "  e=" & word64_to_hex(e);
                report "  h=" & word64_to_hex(h);
            end if;
        end loop;

        -- Update hash values
        H0 := std_logic_vector(unsigned(H0) + unsigned(a));
        H1 := std_logic_vector(unsigned(H1) + unsigned(b));
        H2 := std_logic_vector(unsigned(H2) + unsigned(c));
        H3 := std_logic_vector(unsigned(H3) + unsigned(d));
        H4 := std_logic_vector(unsigned(H4) + unsigned(e));
        H5 := std_logic_vector(unsigned(H5) + unsigned(f));

        report "========================================";
        report "Reference SHA-384(abc):";
        report "H0=" & word64_to_hex(H0);
        report "H1=" & word64_to_hex(H1);
        report "H2=" & word64_to_hex(H2);
        report "H3=" & word64_to_hex(H3);
        report "H4=" & word64_to_hex(H4);
        report "H5=" & word64_to_hex(H5);
        report "========================================";
        report "Expected:";
        report "H0=cb00753f45a35e8b";
        report "H1=b5a03d699ac65007";
        report "H2=272c32ab0eded163";
        report "H3=1a8b605a43ff5bed";
        report "H4=8086072ba1e7cc23";
        report "H5=58baeca134c825a7";

        wait;
    end process;

end architecture sim;
