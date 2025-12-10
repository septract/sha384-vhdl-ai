-------------------------------------------------------------------------------
-- SHA-384 Fast Package
-- High-throughput implementation with CSA support
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package sha384_fast_pkg is

    -- 64-bit word type (SHA-384/512 use 64-bit words)
    subtype word64 is std_logic_vector(63 downto 0);

    -- Array types
    type word64_array is array (natural range <>) of word64;

    -- CSA result type (sum and carry pair)
    type csa_pair is record
        s : word64;  -- Sum
        c : word64;  -- Carry (already shifted left by 1)
    end record;

    -- SHA-384 initial hash values (different from SHA-512)
    constant H0_INIT : word64 := x"cbbb9d5dc1059ed8";
    constant H1_INIT : word64 := x"629a292a367cd507";
    constant H2_INIT : word64 := x"9159015a3070dd17";
    constant H3_INIT : word64 := x"152fecd8f70e5939";
    constant H4_INIT : word64 := x"67332667ffc00b31";
    constant H5_INIT : word64 := x"8eb44a8768581511";
    constant H6_INIT : word64 := x"db0c2e0d64f98fa7";
    constant H7_INIT : word64 := x"47b5481dbefa4fa4";

    -- SHA-384/512 round constants K (80 constants)
    type k_constants_type is array (0 to 79) of word64;
    constant K : k_constants_type := (
        x"428a2f98d728ae22", x"7137449123ef65cd", x"b5c0fbcfec4d3b2f", x"e9b5dba58189dbbc",
        x"3956c25bf348b538", x"59f111f1b605d019", x"923f82a4af194f9b", x"ab1c5ed5da6d8118",
        x"d807aa98a3030242", x"12835b0145706fbe", x"243185be4ee4b28c", x"550c7dc3d5ffb4e2",
        x"72be5d74f27b896f", x"80deb1fe3b1696b1", x"9bdc06a725c71235", x"c19bf174cf692694",
        x"e49b69c19ef14ad2", x"efbe4786384f25e3", x"0fc19dc68b8cd5b5", x"240ca1cc77ac9c65",
        x"2de92c6f592b0275", x"4a7484aa6ea6e483", x"5cb0a9dcbd41fbd4", x"76f988da831153b5",
        x"983e5152ee66dfab", x"a831c66d2db43210", x"b00327c898fb213f", x"bf597fc7beef0ee4",
        x"c6e00bf33da88fc2", x"d5a79147930aa725", x"06ca6351e003826f", x"142929670a0e6e70",
        x"27b70a8546d22ffc", x"2e1b21385c26c926", x"4d2c6dfc5ac42aed", x"53380d139d95b3df",
        x"650a73548baf63de", x"766a0abb3c77b2a8", x"81c2c92e47edaee6", x"92722c851482353b",
        x"a2bfe8a14cf10364", x"a81a664bbc423001", x"c24b8b70d0f89791", x"c76c51a30654be30",
        x"d192e819d6ef5218", x"d69906245565a910", x"f40e35855771202a", x"106aa07032bbd1b8",
        x"19a4c116b8d2d0c8", x"1e376c085141ab53", x"2748774cdf8eeb99", x"34b0bcb5e19b48a8",
        x"391c0cb3c5c95a63", x"4ed8aa4ae3418acb", x"5b9cca4f7763e373", x"682e6ff3d6b2b8a3",
        x"748f82ee5defb2fc", x"78a5636f43172f60", x"84c87814a1f0ab72", x"8cc702081a6439ec",
        x"90befffa23631e28", x"a4506cebde82bde9", x"bef9a3f7b2c67915", x"c67178f2e372532b",
        x"ca273eceea26619c", x"d186b8c721c0c207", x"eada7dd6cde0eb1e", x"f57d4f7fee6ed178",
        x"06f067aa72176fba", x"0a637dc5a2c898a6", x"113f9804bef90dae", x"1b710b35131c471b",
        x"28db77f523047d84", x"32caab7b40c72493", x"3c9ebe0a15c9bebc", x"431d67c49c100d4c",
        x"4cc5d4becb3e42b6", x"597f299cfc657e2a", x"5fcb6fab3ad6faec", x"6c44198c4a475817"
    );

    -- Basic operations
    function rotr64(x : word64; n : natural) return word64;
    function shr64(x : word64; n : natural) return word64;
    function ch(x, y, z : word64) return word64;
    function maj(x, y, z : word64) return word64;
    function big_sigma0(x : word64) return word64;
    function big_sigma1(x : word64) return word64;
    function small_sigma0(x : word64) return word64;
    function small_sigma1(x : word64) return word64;

    -- Carry-Save Adder functions
    function csa_3_2(a, b, c : word64) return csa_pair;
    function csa_reduce(p : csa_pair) return word64;

    -- Multi-operand addition using CSA
    function add5_csa(a, b, c, d, e : word64) return word64;
    function add4_csa(a, b, c, d : word64) return word64;
    function add3_csa(a, b, c : word64) return word64;
    function add2(a, b : word64) return word64;

end package sha384_fast_pkg;

package body sha384_fast_pkg is

    -- Rotate right
    function rotr64(x : word64; n : natural) return word64 is
    begin
        return std_logic_vector(rotate_right(unsigned(x), n));
    end function;

    -- Shift right
    function shr64(x : word64; n : natural) return word64 is
    begin
        return std_logic_vector(shift_right(unsigned(x), n));
    end function;

    -- Ch(x,y,z) = (x AND y) XOR (NOT x AND z)
    function ch(x, y, z : word64) return word64 is
    begin
        return (x and y) xor ((not x) and z);
    end function;

    -- Maj(x,y,z) = (x AND y) XOR (x AND z) XOR (y AND z)
    function maj(x, y, z : word64) return word64 is
    begin
        return (x and y) xor (x and z) xor (y and z);
    end function;

    -- Big Sigma 0: ROTR^28(x) XOR ROTR^34(x) XOR ROTR^39(x)
    function big_sigma0(x : word64) return word64 is
    begin
        return rotr64(x, 28) xor rotr64(x, 34) xor rotr64(x, 39);
    end function;

    -- Big Sigma 1: ROTR^14(x) XOR ROTR^18(x) XOR ROTR^41(x)
    function big_sigma1(x : word64) return word64 is
    begin
        return rotr64(x, 14) xor rotr64(x, 18) xor rotr64(x, 41);
    end function;

    -- Small sigma 0: ROTR^1(x) XOR ROTR^8(x) XOR SHR^7(x)
    function small_sigma0(x : word64) return word64 is
    begin
        return rotr64(x, 1) xor rotr64(x, 8) xor shr64(x, 7);
    end function;

    -- Small sigma 1: ROTR^19(x) XOR ROTR^61(x) XOR SHR^6(x)
    function small_sigma1(x : word64) return word64 is
    begin
        return rotr64(x, 19) xor rotr64(x, 61) xor shr64(x, 6);
    end function;

    ---------------------------------------------------------------------------
    -- Carry-Save Adder (3:2 Compressor)
    -- Reduces 3 operands to 2 (sum + carry) without carry propagation
    -- The carry output is pre-shifted left by 1 for the next stage
    ---------------------------------------------------------------------------
    function csa_3_2(a, b, c : word64) return csa_pair is
        variable result : csa_pair;
        variable carry_raw : word64;
    begin
        -- Sum = a XOR b XOR c
        result.s := a xor b xor c;
        -- Carry = (a AND b) OR (b AND c) OR (a AND c)
        carry_raw := (a and b) or (b and c) or (a and c);
        -- Shift carry left by 1 (carry has weight 2^(i+1) relative to position i)
        result.c := carry_raw(62 downto 0) & '0';
        return result;
    end function;

    ---------------------------------------------------------------------------
    -- Reduce CSA pair to single value using carry-propagate addition
    ---------------------------------------------------------------------------
    function csa_reduce(p : csa_pair) return word64 is
    begin
        return std_logic_vector(unsigned(p.s) + unsigned(p.c));
    end function;

    ---------------------------------------------------------------------------
    -- Add 5 operands using CSA tree
    -- T1 = h + Sigma1(e) + Ch(e,f,g) + K[t] + W[t]
    --
    --     a   b   c   d   e
    --      \  |  /    |   |
    --       CSA1      |   |
    --       /  \      |   |
    --      s1  c1     |   |
    --        \  \    /   /
    --         \  CSA2   /
    --          \  /\   /
    --          s2  c2 /
    --            \  \/
    --             CSA3
    --             /  \
    --            s3  c3
    --              \  /
    --               CPA
    --                |
    --              result
    ---------------------------------------------------------------------------
    function add5_csa(a, b, c, d, e : word64) return word64 is
        variable r1, r2, r3 : csa_pair;
    begin
        r1 := csa_3_2(a, b, c);
        r2 := csa_3_2(r1.s, r1.c, d);
        r3 := csa_3_2(r2.s, r2.c, e);
        return csa_reduce(r3);
    end function;

    ---------------------------------------------------------------------------
    -- Add 4 operands using CSA tree
    -- Used for T1 when K+W is pre-computed: h + Sigma1(e) + Ch(e,f,g) + (K+W)
    ---------------------------------------------------------------------------
    function add4_csa(a, b, c, d : word64) return word64 is
        variable r1, r2 : csa_pair;
    begin
        r1 := csa_3_2(a, b, c);
        r2 := csa_3_2(r1.s, r1.c, d);
        return csa_reduce(r2);
    end function;

    ---------------------------------------------------------------------------
    -- Add 3 operands using CSA
    ---------------------------------------------------------------------------
    function add3_csa(a, b, c : word64) return word64 is
        variable r : csa_pair;
    begin
        r := csa_3_2(a, b, c);
        return csa_reduce(r);
    end function;

    ---------------------------------------------------------------------------
    -- Simple 2-operand addition
    -- T2 = Sigma0(a) + Maj(a,b,c)
    ---------------------------------------------------------------------------
    function add2(a, b : word64) return word64 is
    begin
        return std_logic_vector(unsigned(a) + unsigned(b));
    end function;

end package body sha384_fast_pkg;
