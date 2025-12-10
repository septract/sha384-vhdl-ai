-------------------------------------------------------------------------------
-- SHA-384 Fast Core
-- High-throughput implementation with 4x loop unrolling and CSA
--
-- Optimizations:
--   - 4x loop unrolling: 4 rounds per clock cycle (20 cycles for compression)
--   - Carry-Save Adders: Reduced critical path
--   - 128-bit data input: 8 cycles to load block instead of 16
--   - Circular W buffer: No array shifting
--   - K+W pre-computation: Reduces T1 from 5 operands to 4
--
-- Interface:
--   clk        : Clock input
--   reset      : Synchronous reset (active high)
--   start      : Start hashing a new message
--   data_in    : 128-bit input data (2 words per cycle)
--   data_valid : Input data is valid
--   last_block : This is the last block (message already padded)
--   ready      : Core is ready to accept data
--   hash_out   : 384-bit hash output
--   hash_valid : Hash output is valid
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_fast_pkg.all;

entity sha384_fast is
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        start      : in  std_logic;
        data_in    : in  std_logic_vector(127 downto 0);  -- 2 words per cycle
        data_valid : in  std_logic;
        last_block : in  std_logic;
        ready      : out std_logic;
        hash_out   : out std_logic_vector(383 downto 0);
        hash_valid : out std_logic
    );
end entity sha384_fast;

architecture rtl of sha384_fast is

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
    signal word_count : unsigned(2 downto 0);   -- 0-7 for loading 8 pairs of words
    signal round_base : unsigned(6 downto 0);   -- 0, 4, 8, ... 76 (increments by 4)

    -- Flag for last block
    signal is_last_block : std_logic;

    -- Pre-computed K+W values (computed one cycle ahead)
    signal kw_pre : word64_array(0 to 3);

    -- Function to compute W index with circular addressing
    -- For round t, we need W[t mod 16]
    function w_idx(t : unsigned) return integer is
    begin
        return to_integer(t(3 downto 0));
    end function;

begin

    -- Main process
    process(clk)
        -- W values for current 4 rounds
        variable w0, w1, w2, w3 : word64;
        -- Pre-computed K+W values (from registered kw_pre)
        variable kw0, kw1, kw2, kw3 : word64;
        -- Working variables (local copies for combinational logic)
        variable a, b, c, d, e, f, g, h : word64;
        -- Intermediate values for round 0
        variable T1_0, T2_0, a0, e0 : word64;
        -- Intermediate values for round 1
        variable T1_1, T2_1, a1, e1 : word64;
        -- Intermediate values for round 2
        variable T1_2, T2_2, a2, e2 : word64;
        -- Intermediate values for round 3
        variable T1_3, T2_3, a3, e3 : word64;
        -- New W values for schedule extension
        variable w_new0, w_new1, w_new2, w_new3 : word64;
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
                            -- Load 2 words per cycle (128 bits)
                            -- data_in(127:64) = first word, data_in(63:0) = second word
                            W(to_integer(word_count & '0'))     <= data_in(127 downto 64);
                            W(to_integer(word_count & '1'))     <= data_in(63 downto 0);
                            is_last_block <= last_block;

                            if word_count = 7 then
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

                                -- Pre-compute K[0..3] + W[0..3] for first compress cycle
                                -- Note: data_in contains W[14..15], W[0..13] already loaded
                                kw_pre(0) <= add2(K(0), W(0));
                                kw_pre(1) <= add2(K(1), W(1));
                                kw_pre(2) <= add2(K(2), W(2));
                                kw_pre(3) <= add2(K(3), W(3));

                                state <= COMPRESS;
                            else
                                word_count <= word_count + 1;
                            end if;
                        end if;

                    when COMPRESS =>
                        -- Current round base
                        t := round_base;

                        -- Use pre-computed K+W values from previous cycle
                        kw0 := kw_pre(0);
                        kw1 := kw_pre(1);
                        kw2 := kw_pre(2);
                        kw3 := kw_pre(3);

                        -- Get/compute W values for rounds t, t+1, t+2, t+3
                        if t < 16 then
                            -- First 4 iterations (t=0,4,8,12): use message words directly
                            w0 := W(w_idx(t));
                            w1 := W(w_idx(t + 1));
                            w2 := W(w_idx(t + 2));
                            w3 := W(w_idx(t + 3));
                        else
                            -- Compute 4 new W values
                            -- W[t] = sigma1(W[t-2]) + W[t-7] + sigma0(W[t-15]) + W[t-16]
                            -- Note: All indices are mod 16 due to circular buffer

                            -- W[t] uses W[t-2], W[t-7], W[t-15], W[t-16]
                            w_new0 := std_logic_vector(
                                unsigned(small_sigma1(W(w_idx(t - 2)))) +
                                unsigned(W(w_idx(t - 7))) +
                                unsigned(small_sigma0(W(w_idx(t - 15)))) +
                                unsigned(W(w_idx(t - 16)))
                            );

                            -- W[t+1] uses W[t-1], W[t-6], W[t-14], W[t-15]
                            w_new1 := std_logic_vector(
                                unsigned(small_sigma1(W(w_idx(t - 1)))) +
                                unsigned(W(w_idx(t - 6))) +
                                unsigned(small_sigma0(W(w_idx(t - 14)))) +
                                unsigned(W(w_idx(t - 15)))
                            );

                            -- W[t+2] uses W[t], W[t-5], W[t-13], W[t-14]
                            -- Note: W[t] = w_new0 (just computed)
                            w_new2 := std_logic_vector(
                                unsigned(small_sigma1(w_new0)) +
                                unsigned(W(w_idx(t - 5))) +
                                unsigned(small_sigma0(W(w_idx(t - 13)))) +
                                unsigned(W(w_idx(t - 14)))
                            );

                            -- W[t+3] uses W[t+1], W[t-4], W[t-12], W[t-13]
                            -- Note: W[t+1] = w_new1 (just computed)
                            w_new3 := std_logic_vector(
                                unsigned(small_sigma1(w_new1)) +
                                unsigned(W(w_idx(t - 4))) +
                                unsigned(small_sigma0(W(w_idx(t - 12)))) +
                                unsigned(W(w_idx(t - 13)))
                            );

                            w0 := w_new0;
                            w1 := w_new1;
                            w2 := w_new2;
                            w3 := w_new3;

                            -- Update W array for future rounds
                            W(w_idx(t))     <= w_new0;
                            W(w_idx(t + 1)) <= w_new1;
                            W(w_idx(t + 2)) <= w_new2;
                            W(w_idx(t + 3)) <= w_new3;
                        end if;

                        -- Load working variables
                        a := va; b := vb; c := vc; d := vd;
                        e := ve; f := vf; g := vg; h := vh;

                        -------------------------------------------------------
                        -- Round t (first of 4)
                        -- T1 = h + Sigma1(e) + Ch(e,f,g) + (K[t] + W[t])
                        -- Using pre-computed K+W reduces from 5 operands to 4
                        -------------------------------------------------------
                        T1_0 := add4_csa(h, big_sigma1(e), ch(e, f, g), kw0);
                        -- T2 = Sigma0(a) + Maj(a,b,c)
                        T2_0 := add2(big_sigma0(a), maj(a, b, c));
                        -- New values
                        a0 := add2(T1_0, T2_0);
                        e0 := add2(d, T1_0);

                        -------------------------------------------------------
                        -- Round t+1 (second of 4)
                        -- After round t: (a,b,c,d,e,f,g,h) = (a0,a,b,c,e0,e,f,g)
                        -------------------------------------------------------
                        T1_1 := add4_csa(g, big_sigma1(e0), ch(e0, e, f), kw1);
                        T2_1 := add2(big_sigma0(a0), maj(a0, a, b));
                        a1 := add2(T1_1, T2_1);
                        e1 := add2(c, T1_1);

                        -------------------------------------------------------
                        -- Round t+2 (third of 4)
                        -- After round t+1: (a,b,c,d,e,f,g,h) = (a1,a0,a,b,e1,e0,e,f)
                        -------------------------------------------------------
                        T1_2 := add4_csa(f, big_sigma1(e1), ch(e1, e0, e), kw2);
                        T2_2 := add2(big_sigma0(a1), maj(a1, a0, a));
                        a2 := add2(T1_2, T2_2);
                        e2 := add2(b, T1_2);

                        -------------------------------------------------------
                        -- Round t+3 (fourth of 4)
                        -- After round t+2: (a,b,c,d,e,f,g,h) = (a2,a1,a0,a,e2,e1,e0,e)
                        -------------------------------------------------------
                        T1_3 := add4_csa(e, big_sigma1(e2), ch(e2, e1, e0), kw3);
                        T2_3 := add2(big_sigma0(a2), maj(a2, a1, a0));
                        a3 := add2(T1_3, T2_3);
                        e3 := add2(a, T1_3);

                        -------------------------------------------------------
                        -- Update registered working variables
                        -- Final state: (a,b,c,d,e,f,g,h) = (a3,a2,a1,a0,e3,e2,e1,e0)
                        -------------------------------------------------------
                        va <= a3;
                        vb <= a2;
                        vc <= a1;
                        vd <= a0;
                        ve <= e3;
                        vf <= e2;
                        vg <= e1;
                        vh <= e0;

                        -- Check if done (80 rounds = 20 iterations of 4)
                        if round_base = 76 then
                            state <= UPDATE_HASH;
                        else
                            round_base <= round_base + 4;

                            -- Pre-compute K+W for next cycle (rounds t+4 to t+7)
                            -- For t+4 < 16: W values are direct from buffer
                            -- For t+4 >= 16: W values just computed (w0..w3) and buffer
                            if t + 4 < 16 then
                                -- Next iteration uses message words directly
                                kw_pre(0) <= add2(K(to_integer(t + 4)), W(w_idx(t + 4)));
                                kw_pre(1) <= add2(K(to_integer(t + 5)), W(w_idx(t + 5)));
                                kw_pre(2) <= add2(K(to_integer(t + 6)), W(w_idx(t + 6)));
                                kw_pre(3) <= add2(K(to_integer(t + 7)), W(w_idx(t + 7)));
                            else
                                -- Next iteration needs computed W values
                                -- W[t+4..t+7] will be computed next cycle, use formula
                                -- For pre-computation we compute K + W where W comes from:
                                -- W[t+4] = sigma1(W[t+2]) + W[t-3] + sigma0(W[t-11]) + W[t-12]
                                -- But W[t+2] = w2 (computed this cycle for t >= 16) or W(t+2) for t < 16
                                -- This is complex, so for t >= 12, we compute inline next cycle
                                -- For t = 12: t+4 = 16, need to compute W[16..19]
                                -- Use the newly computed w0..w3 which are W[t..t+3]
                                kw_pre(0) <= add2(K(to_integer(t + 4)), std_logic_vector(
                                    unsigned(small_sigma1(w2)) +
                                    unsigned(W(w_idx(t - 3))) +
                                    unsigned(small_sigma0(W(w_idx(t - 11)))) +
                                    unsigned(W(w_idx(t - 12)))));
                                kw_pre(1) <= add2(K(to_integer(t + 5)), std_logic_vector(
                                    unsigned(small_sigma1(w3)) +
                                    unsigned(W(w_idx(t - 2))) +
                                    unsigned(small_sigma0(W(w_idx(t - 10)))) +
                                    unsigned(W(w_idx(t - 11)))));
                                -- W[t+6] depends on W[t+4] which we just computed inline above
                                -- This creates a dependency chain - compute simpler version
                                kw_pre(2) <= add2(K(to_integer(t + 6)), std_logic_vector(
                                    unsigned(small_sigma1(std_logic_vector(
                                        unsigned(small_sigma1(w2)) +
                                        unsigned(W(w_idx(t - 3))) +
                                        unsigned(small_sigma0(W(w_idx(t - 11)))) +
                                        unsigned(W(w_idx(t - 12)))))) +
                                    unsigned(W(w_idx(t - 1))) +
                                    unsigned(small_sigma0(W(w_idx(t - 9)))) +
                                    unsigned(W(w_idx(t - 10)))));
                                kw_pre(3) <= add2(K(to_integer(t + 7)), std_logic_vector(
                                    unsigned(small_sigma1(std_logic_vector(
                                        unsigned(small_sigma1(w3)) +
                                        unsigned(W(w_idx(t - 2))) +
                                        unsigned(small_sigma0(W(w_idx(t - 10)))) +
                                        unsigned(W(w_idx(t - 11)))))) +
                                    unsigned(w0) +
                                    unsigned(small_sigma0(W(w_idx(t - 8)))) +
                                    unsigned(W(w_idx(t - 9)))));
                            end if;
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
