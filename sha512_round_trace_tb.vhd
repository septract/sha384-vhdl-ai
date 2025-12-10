-------------------------------------------------------------------------------
-- SHA-512 Round Trace - print values after each round
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity sha512_round_trace_tb is
end entity sha512_round_trace_tb;

architecture sim of sha512_round_trace_tb is

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

    -- SHA-512 initial hash values
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

        -- Print W values at key positions
        report "W[0] = " & word64_to_hex(W(0));
        report "W[15] = " & word64_to_hex(W(15));
        report "W[16] = " & word64_to_hex(W(16));
        report "W[17] = " & word64_to_hex(W(17));
        report "W[18] = " & word64_to_hex(W(18));
        report "W[19] = " & word64_to_hex(W(19));
        report "W[20] = " & word64_to_hex(W(20));

        -- Initialize working variables
        a := SHA512_H0; b := SHA512_H1; c := SHA512_H2; d := SHA512_H3;
        e := SHA512_H4; f := SHA512_H5; g := SHA512_H6; h := SHA512_H7;

        report "Initial state:";
        report "  a=" & word64_to_hex(a) & " e=" & word64_to_hex(e);

        -- 80 rounds with tracing
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

            -- Print state after selected rounds
            if t < 5 or t = 10 or t = 20 or t = 40 or t = 60 or t = 79 then
                report "After round " & integer'image(t) & ": a=" & word64_to_hex(a) & " e=" & word64_to_hex(e);
            end if;
        end loop;

        -- Final values before adding to hash
        report "Final working vars:";
        report "  a=" & word64_to_hex(a);
        report "  b=" & word64_to_hex(b);
        report "  c=" & word64_to_hex(c);
        report "  d=" & word64_to_hex(d);

        wait;
    end process;

end architecture sim;
