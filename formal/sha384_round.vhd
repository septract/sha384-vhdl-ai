-- SHA-384 Single Round Function (Combinational)
-- Pure combinational logic for SAW formal verification
--
-- Computes one SHA-384 compression round:
--   T1 = h + Σ1(e) + Ch(e,f,g) + K + W
--   T2 = Σ0(a) + Maj(a,b,c)
--   New state: (T1+T2, a, b, c, d+T1, e, f, g)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sha384_round is
    port (
        -- Input working variables
        a_in, b_in, c_in, d_in : in std_logic_vector(63 downto 0);
        e_in, f_in, g_in, h_in : in std_logic_vector(63 downto 0);
        -- Round constant and message schedule word
        k : in std_logic_vector(63 downto 0);
        w : in std_logic_vector(63 downto 0);
        -- Output working variables
        a_out, b_out, c_out, d_out : out std_logic_vector(63 downto 0);
        e_out, f_out, g_out, h_out : out std_logic_vector(63 downto 0)
    );
end entity sha384_round;

architecture rtl of sha384_round is
    -- Rotate right function
    function rotr64(x : std_logic_vector(63 downto 0); n : integer)
        return std_logic_vector is
    begin
        return x(n-1 downto 0) & x(63 downto n);
    end function;

    -- Big Sigma 0: ROTR^28(x) XOR ROTR^34(x) XOR ROTR^39(x)
    function big_sigma0(x : std_logic_vector(63 downto 0))
        return std_logic_vector is
    begin
        return rotr64(x, 28) xor rotr64(x, 34) xor rotr64(x, 39);
    end function;

    -- Big Sigma 1: ROTR^14(x) XOR ROTR^18(x) XOR ROTR^41(x)
    function big_sigma1(x : std_logic_vector(63 downto 0))
        return std_logic_vector is
    begin
        return rotr64(x, 14) xor rotr64(x, 18) xor rotr64(x, 41);
    end function;

    -- Ch(x,y,z) = (x AND y) XOR (NOT x AND z)
    function ch(x, y, z : std_logic_vector(63 downto 0))
        return std_logic_vector is
    begin
        return (x and y) xor (not x and z);
    end function;

    -- Maj(x,y,z) = (x AND y) XOR (x AND z) XOR (y AND z)
    function maj(x, y, z : std_logic_vector(63 downto 0))
        return std_logic_vector is
    begin
        return (x and y) xor (x and z) xor (y and z);
    end function;

    signal t1, t2 : std_logic_vector(63 downto 0);

begin
    -- T1 = h + Σ1(e) + Ch(e,f,g) + K + W
    t1 <= std_logic_vector(
        unsigned(h_in) +
        unsigned(big_sigma1(e_in)) +
        unsigned(ch(e_in, f_in, g_in)) +
        unsigned(k) +
        unsigned(w)
    );

    -- T2 = Σ0(a) + Maj(a,b,c)
    t2 <= std_logic_vector(
        unsigned(big_sigma0(a_in)) +
        unsigned(maj(a_in, b_in, c_in))
    );

    -- Update working variables
    a_out <= std_logic_vector(unsigned(t1) + unsigned(t2));  -- a = T1 + T2
    b_out <= a_in;                                            -- b = a
    c_out <= b_in;                                            -- c = b
    d_out <= c_in;                                            -- d = c
    e_out <= std_logic_vector(unsigned(d_in) + unsigned(t1)); -- e = d + T1
    f_out <= e_in;                                            -- f = e
    g_out <= f_in;                                            -- g = f
    h_out <= g_in;                                            -- h = g

end architecture rtl;
