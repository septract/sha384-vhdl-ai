-------------------------------------------------------------------------------
-- SHA-384 Fast8 Core
-- High-throughput implementation with 8x loop unrolling
--
-- Optimizations:
--   - 8x loop unrolling: 8 rounds per clock cycle (10 cycles for compression)
--   - Carry-Save Adders: Reduced critical path
--   - 512-bit data input: 2 cycles to load block instead of 16
--   - Circular W buffer: No array shifting
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_fast_pkg.all;

entity sha384_fast8 is
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        start      : in  std_logic;
        data_in    : in  std_logic_vector(511 downto 0);  -- 8 words per cycle
        data_valid : in  std_logic;
        last_block : in  std_logic;
        ready      : out std_logic;
        hash_out   : out std_logic_vector(383 downto 0);
        hash_valid : out std_logic
    );
end entity sha384_fast8;

architecture rtl of sha384_fast8 is

    -- State machine states
    type state_type is (IDLE, LOAD_BLOCK, COMPRESS, UPDATE_HASH, DONE);
    signal state : state_type;

    -- Hash values (H0-H7), only H0-H5 used for output
    signal hv : word64_array(0 to 7);

    -- Working variables
    signal va, vb, vc, vd, ve, vf, vg, vh : word64;

    -- Message schedule array W (16 words)
    signal W : word64_array(0 to 15);

    -- Counters
    signal word_count : unsigned(0 downto 0);   -- 0-1 for loading 2 sets of 8 words
    signal round_base : unsigned(6 downto 0);   -- 0, 8, 16, ... 72 (increments by 8)

    -- Flag for last block
    signal is_last_block : std_logic;

    -- Function to compute W index with circular addressing
    function w_idx(t : unsigned) return integer is
    begin
        return to_integer(t(3 downto 0));
    end function;

begin

    -- Main process
    process(clk)
        -- W values for current 8 rounds
        variable w0, w1, w2, w3, w4, w5, w6, w7 : word64;
        -- K+W values
        variable kw0, kw1, kw2, kw3, kw4, kw5, kw6, kw7 : word64;
        -- Working variables (local copies for combinational logic)
        variable a, b, c, d, e, f, g, h : word64;
        -- Intermediate values for rounds 0-7
        variable T1_0, T2_0, a0, e0 : word64;
        variable T1_1, T2_1, a1, e1 : word64;
        variable T1_2, T2_2, a2, e2 : word64;
        variable T1_3, T2_3, a3, e3 : word64;
        variable T1_4, T2_4, a4, e4 : word64;
        variable T1_5, T2_5, a5, e5 : word64;
        variable T1_6, T2_6, a6, e6 : word64;
        variable T1_7, T2_7, a7, e7 : word64;
        -- Round number
        variable t : unsigned(6 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state        <= IDLE;
                hash_valid   <= '0';
                ready        <= '1';
                word_count   <= (others => '0');
                round_base   <= (others => '0');
                is_last_block <= '0';

                -- Initialize hash values
                hv(0) <= H0_INIT;
                hv(1) <= H1_INIT;
                hv(2) <= H2_INIT;
                hv(3) <= H3_INIT;
                hv(4) <= H4_INIT;
                hv(5) <= H5_INIT;
                hv(6) <= H6_INIT;
                hv(7) <= H7_INIT;

            else
                case state is
                    when IDLE =>
                        hash_valid <= '0';
                        ready      <= '1';

                        if start = '1' then
                            -- Re-initialize hash for new message
                            hv(0) <= H0_INIT;
                            hv(1) <= H1_INIT;
                            hv(2) <= H2_INIT;
                            hv(3) <= H3_INIT;
                            hv(4) <= H4_INIT;
                            hv(5) <= H5_INIT;
                            hv(6) <= H6_INIT;
                            hv(7) <= H7_INIT;
                            word_count <= (others => '0');
                            state <= LOAD_BLOCK;
                        end if;

                    when LOAD_BLOCK =>
                        ready <= '1';

                        if data_valid = '1' then
                            -- Load 8 words per cycle (512 bits)
                            if word_count = 0 then
                                W(0) <= data_in(511 downto 448);
                                W(1) <= data_in(447 downto 384);
                                W(2) <= data_in(383 downto 320);
                                W(3) <= data_in(319 downto 256);
                                W(4) <= data_in(255 downto 192);
                                W(5) <= data_in(191 downto 128);
                                W(6) <= data_in(127 downto 64);
                                W(7) <= data_in(63 downto 0);
                                word_count <= "1";
                            else
                                W(8)  <= data_in(511 downto 448);
                                W(9)  <= data_in(447 downto 384);
                                W(10) <= data_in(383 downto 320);
                                W(11) <= data_in(319 downto 256);
                                W(12) <= data_in(255 downto 192);
                                W(13) <= data_in(191 downto 128);
                                W(14) <= data_in(127 downto 64);
                                W(15) <= data_in(63 downto 0);
                                is_last_block <= last_block;

                                word_count <= (others => '0');
                                round_base <= (others => '0');
                                ready      <= '0';

                                -- Initialize working variables from current hash
                                va <= hv(0);
                                vb <= hv(1);
                                vc <= hv(2);
                                vd <= hv(3);
                                ve <= hv(4);
                                vf <= hv(5);
                                vg <= hv(6);
                                vh <= hv(7);

                                state <= COMPRESS;
                            end if;
                        end if;

                    when COMPRESS =>
                        -- Current round base
                        t := round_base;

                        -- Get/compute W values for rounds t to t+7
                        if t < 16 then
                            -- First 2 iterations (t=0,8): use message words directly
                            w0 := W(w_idx(t));
                            w1 := W(w_idx(t + 1));
                            w2 := W(w_idx(t + 2));
                            w3 := W(w_idx(t + 3));
                            w4 := W(w_idx(t + 4));
                            w5 := W(w_idx(t + 5));
                            w6 := W(w_idx(t + 6));
                            w7 := W(w_idx(t + 7));
                        else
                            -- Compute 8 new W values with dependency chain
                            -- W[t] = sigma1(W[t-2]) + W[t-7] + sigma0(W[t-15]) + W[t-16]

                            -- w0 and w1 only depend on buffer values
                            w0 := std_logic_vector(
                                unsigned(small_sigma1(W(w_idx(t - 2)))) +
                                unsigned(W(w_idx(t - 7))) +
                                unsigned(small_sigma0(W(w_idx(t - 15)))) +
                                unsigned(W(w_idx(t - 16)))
                            );

                            w1 := std_logic_vector(
                                unsigned(small_sigma1(W(w_idx(t - 1)))) +
                                unsigned(W(w_idx(t - 6))) +
                                unsigned(small_sigma0(W(w_idx(t - 14)))) +
                                unsigned(W(w_idx(t - 15)))
                            );

                            -- w2 depends on w0
                            w2 := std_logic_vector(
                                unsigned(small_sigma1(w0)) +
                                unsigned(W(w_idx(t - 5))) +
                                unsigned(small_sigma0(W(w_idx(t - 13)))) +
                                unsigned(W(w_idx(t - 14)))
                            );

                            -- w3 depends on w1
                            w3 := std_logic_vector(
                                unsigned(small_sigma1(w1)) +
                                unsigned(W(w_idx(t - 4))) +
                                unsigned(small_sigma0(W(w_idx(t - 12)))) +
                                unsigned(W(w_idx(t - 13)))
                            );

                            -- w4 depends on w2
                            w4 := std_logic_vector(
                                unsigned(small_sigma1(w2)) +
                                unsigned(W(w_idx(t - 3))) +
                                unsigned(small_sigma0(W(w_idx(t - 11)))) +
                                unsigned(W(w_idx(t - 12)))
                            );

                            -- w5 depends on w3
                            w5 := std_logic_vector(
                                unsigned(small_sigma1(w3)) +
                                unsigned(W(w_idx(t - 2))) +
                                unsigned(small_sigma0(W(w_idx(t - 10)))) +
                                unsigned(W(w_idx(t - 11)))
                            );

                            -- w6 depends on w4
                            w6 := std_logic_vector(
                                unsigned(small_sigma1(w4)) +
                                unsigned(W(w_idx(t - 1))) +
                                unsigned(small_sigma0(W(w_idx(t - 9)))) +
                                unsigned(W(w_idx(t - 10)))
                            );

                            -- w7 depends on w5 and w0
                            w7 := std_logic_vector(
                                unsigned(small_sigma1(w5)) +
                                unsigned(w0) +
                                unsigned(small_sigma0(W(w_idx(t - 8)))) +
                                unsigned(W(w_idx(t - 9)))
                            );

                            -- Update W array for future rounds
                            W(w_idx(t))     <= w0;
                            W(w_idx(t + 1)) <= w1;
                            W(w_idx(t + 2)) <= w2;
                            W(w_idx(t + 3)) <= w3;
                            W(w_idx(t + 4)) <= w4;
                            W(w_idx(t + 5)) <= w5;
                            W(w_idx(t + 6)) <= w6;
                            W(w_idx(t + 7)) <= w7;
                        end if;

                        -- Compute K+W values
                        kw0 := add2(K(to_integer(t)), w0);
                        kw1 := add2(K(to_integer(t + 1)), w1);
                        kw2 := add2(K(to_integer(t + 2)), w2);
                        kw3 := add2(K(to_integer(t + 3)), w3);
                        kw4 := add2(K(to_integer(t + 4)), w4);
                        kw5 := add2(K(to_integer(t + 5)), w5);
                        kw6 := add2(K(to_integer(t + 6)), w6);
                        kw7 := add2(K(to_integer(t + 7)), w7);

                        -- Load working variables
                        a := va; b := vb; c := vc; d := vd;
                        e := ve; f := vf; g := vg; h := vh;

                        -------------------------------------------------------
                        -- Round t (first of 8)
                        -- State: (a, b, c, d, e, f, g, h)
                        -- T1 = h + Σ1(e) + Ch(e,f,g) + K[t] + W[t]
                        -------------------------------------------------------
                        T1_0 := add4_csa(h, big_sigma1(e), ch(e, f, g), kw0);
                        T2_0 := add2(big_sigma0(a), maj(a, b, c));
                        a0 := add2(T1_0, T2_0);
                        e0 := add2(d, T1_0);

                        -------------------------------------------------------
                        -- Round t+1
                        -- State: (a0, a, b, c, e0, e, f, g)
                        -------------------------------------------------------
                        T1_1 := add4_csa(g, big_sigma1(e0), ch(e0, e, f), kw1);
                        T2_1 := add2(big_sigma0(a0), maj(a0, a, b));
                        a1 := add2(T1_1, T2_1);
                        e1 := add2(c, T1_1);

                        -------------------------------------------------------
                        -- Round t+2
                        -- State: (a1, a0, a, b, e1, e0, e, f)
                        -------------------------------------------------------
                        T1_2 := add4_csa(f, big_sigma1(e1), ch(e1, e0, e), kw2);
                        T2_2 := add2(big_sigma0(a1), maj(a1, a0, a));
                        a2 := add2(T1_2, T2_2);
                        e2 := add2(b, T1_2);

                        -------------------------------------------------------
                        -- Round t+3
                        -- State: (a2, a1, a0, a, e2, e1, e0, e)
                        -------------------------------------------------------
                        T1_3 := add4_csa(e, big_sigma1(e2), ch(e2, e1, e0), kw3);
                        T2_3 := add2(big_sigma0(a2), maj(a2, a1, a0));
                        a3 := add2(T1_3, T2_3);
                        e3 := add2(a, T1_3);

                        -------------------------------------------------------
                        -- Round t+4
                        -- State: (a3, a2, a1, a0, e3, e2, e1, e0)
                        -------------------------------------------------------
                        T1_4 := add4_csa(e0, big_sigma1(e3), ch(e3, e2, e1), kw4);
                        T2_4 := add2(big_sigma0(a3), maj(a3, a2, a1));
                        a4 := add2(T1_4, T2_4);
                        e4 := add2(a0, T1_4);

                        -------------------------------------------------------
                        -- Round t+5
                        -- State: (a4, a3, a2, a1, e4, e3, e2, e1)
                        -------------------------------------------------------
                        T1_5 := add4_csa(e1, big_sigma1(e4), ch(e4, e3, e2), kw5);
                        T2_5 := add2(big_sigma0(a4), maj(a4, a3, a2));
                        a5 := add2(T1_5, T2_5);
                        e5 := add2(a1, T1_5);

                        -------------------------------------------------------
                        -- Round t+6
                        -- State: (a5, a4, a3, a2, e5, e4, e3, e2)
                        -------------------------------------------------------
                        T1_6 := add4_csa(e2, big_sigma1(e5), ch(e5, e4, e3), kw6);
                        T2_6 := add2(big_sigma0(a5), maj(a5, a4, a3));
                        a6 := add2(T1_6, T2_6);
                        e6 := add2(a2, T1_6);

                        -------------------------------------------------------
                        -- Round t+7
                        -- State: (a6, a5, a4, a3, e6, e5, e4, e3)
                        -------------------------------------------------------
                        T1_7 := add4_csa(e3, big_sigma1(e6), ch(e6, e5, e4), kw7);
                        T2_7 := add2(big_sigma0(a6), maj(a6, a5, a4));
                        a7 := add2(T1_7, T2_7);
                        e7 := add2(a3, T1_7);

                        -------------------------------------------------------
                        -- Update registered working variables
                        -- Final state: (a7, a6, a5, a4, e7, e6, e5, e4)
                        -------------------------------------------------------
                        va <= a7;
                        vb <= a6;
                        vc <= a5;
                        vd <= a4;
                        ve <= e7;
                        vf <= e6;
                        vg <= e5;
                        vh <= e4;

                        -- Check if done (80 rounds = 10 iterations of 8)
                        if round_base = 72 then
                            state <= UPDATE_HASH;
                        else
                            round_base <= round_base + 8;
                        end if;

                    when UPDATE_HASH =>
                        -- Add compressed chunk to current hash value
                        hv(0) <= std_logic_vector(unsigned(hv(0)) + unsigned(va));
                        hv(1) <= std_logic_vector(unsigned(hv(1)) + unsigned(vb));
                        hv(2) <= std_logic_vector(unsigned(hv(2)) + unsigned(vc));
                        hv(3) <= std_logic_vector(unsigned(hv(3)) + unsigned(vd));
                        hv(4) <= std_logic_vector(unsigned(hv(4)) + unsigned(ve));
                        hv(5) <= std_logic_vector(unsigned(hv(5)) + unsigned(vf));
                        hv(6) <= std_logic_vector(unsigned(hv(6)) + unsigned(vg));
                        hv(7) <= std_logic_vector(unsigned(hv(7)) + unsigned(vh));

                        if is_last_block = '1' then
                            state <= DONE;
                        else
                            word_count <= (others => '0');
                            state <= LOAD_BLOCK;
                        end if;

                    when DONE =>
                        hash_valid <= '1';
                        ready      <= '1';

                        if start = '1' then
                            hash_valid <= '0';
                            -- Re-initialize hash for new message
                            hv(0) <= H0_INIT;
                            hv(1) <= H1_INIT;
                            hv(2) <= H2_INIT;
                            hv(3) <= H3_INIT;
                            hv(4) <= H4_INIT;
                            hv(5) <= H5_INIT;
                            hv(6) <= H6_INIT;
                            hv(7) <= H7_INIT;
                            word_count <= (others => '0');
                            state <= LOAD_BLOCK;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- Output hash (SHA-384 uses only first 6 words = 384 bits)
    hash_out <= hv(0) & hv(1) & hv(2) & hv(3) & hv(4) & hv(5);

end architecture rtl;
