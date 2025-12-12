-------------------------------------------------------------------------------
-- SHA-384 Pipelined Core
-- Maximum throughput implementation with full pipelining
--
-- Optimizations implemented:
--   1. Full pipelining: 10 stages, 1 block/cycle throughput (after fill)
--   2. 1024-bit data input: Full block in single cycle
--   3. Merged state machine: No overhead states
--   4. Speculative W pre-computation: W computed in parallel
--   5. 8x loop unrolling per stage: 8 rounds/stage
--
-- Performance:
--   Latency: 10 cycles per block
--   Throughput: 1 block per cycle (after pipeline fills)
--
-- Interface:
--   - Set start=1 and provide first block to begin new message
--   - Continue providing blocks with data_valid=1
--   - Set last_block=1 with final block of message
--   - Hash outputs appear 10 cycles later on hash_out when hash_valid=1
--   - Ready indicates pipeline can accept new block
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_fast_pkg.all;

entity sha384_pipeline is
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        -- Input interface (1024-bit = full block)
        start      : in  std_logic;                        -- Start new message
        data_in    : in  std_logic_vector(1023 downto 0);  -- Full 1024-bit block
        data_valid : in  std_logic;                        -- Input data valid
        last_block : in  std_logic;                        -- This is the final block
        ready      : out std_logic;                        -- Ready to accept data
        -- Hash state input (for multi-block continuation)
        h_in       : in  std_logic_vector(511 downto 0);   -- Current hash state (8x64)
        use_h_in   : in  std_logic;                        -- Use h_in instead of H_INIT
        -- Output interface
        hash_out   : out std_logic_vector(383 downto 0);   -- 384-bit hash output
        hash_valid : out std_logic;                        -- Hash output valid
        -- For multi-block: output intermediate hash for next block
        h_out      : out std_logic_vector(511 downto 0);   -- Updated hash state
        h_out_valid: out std_logic                         -- h_out is valid (block done)
    );
end entity sha384_pipeline;

architecture rtl of sha384_pipeline is

    -- Pipeline stage record
    type stage_data is record
        valid      : std_logic;
        last       : std_logic;
        hv         : word64_array(0 to 7);  -- Hash values for this block
        va, vb, vc, vd, ve, vf, vg, vh : word64;  -- Working variables
        W          : word64_array(0 to 15); -- Message schedule buffer
    end record stage_data;

    type stage_array is array (0 to 9) of stage_data;
    signal stages : stage_array;

    -- Constants for initialization
    constant STAGE_INIT : stage_data := (
        valid => '0',
        last  => '0',
        hv    => (H0_INIT, H1_INIT, H2_INIT, H3_INIT, H4_INIT, H5_INIT, H6_INIT, H7_INIT),
        va => (others => '0'), vb => (others => '0'), vc => (others => '0'), vd => (others => '0'),
        ve => (others => '0'), vf => (others => '0'), vg => (others => '0'), vh => (others => '0'),
        W => (others => (others => '0'))
    );

    -- Function to compute W index with circular addressing
    function w_idx(t : integer) return integer is
    begin
        return t mod 16;
    end function;

begin

    -- Always ready (pipeline can always accept)
    ready <= '1';

    -- Main pipeline process
    process(clk)
        variable new_stage0 : stage_data;
        variable w0, w1, w2, w3, w4, w5, w6, w7 : word64;
        variable kw0, kw1, kw2, kw3, kw4, kw5, kw6, kw7 : word64;
        variable a, b, c, d, e, f, g, h : word64;
        variable T1_0, T2_0, a0, e0 : word64;
        variable T1_1, T2_1, a1, e1 : word64;
        variable T1_2, T2_2, a2, e2 : word64;
        variable T1_3, T2_3, a3, e3 : word64;
        variable T1_4, T2_4, a4, e4 : word64;
        variable T1_5, T2_5, a5, e5 : word64;
        variable T1_6, T2_6, a6, e6 : word64;
        variable T1_7, T2_7, a7, e7 : word64;
        variable W_buf : word64_array(0 to 15);
        variable t : integer;
        variable final_hv : word64_array(0 to 7);
        variable stage_in : stage_data;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                -- Reset all pipeline stages
                for i in 0 to 9 loop
                    stages(i) <= STAGE_INIT;
                end loop;
                hash_valid <= '0';
                h_out_valid <= '0';
            else
                -- Default outputs
                hash_valid <= '0';
                h_out_valid <= '0';

                ---------------------------------------------------------
                -- Stage 0: Load new block into pipeline
                ---------------------------------------------------------
                if data_valid = '1' then
                    new_stage0.valid := '1';
                    new_stage0.last := last_block;

                    -- Set initial hash values
                    if start = '1' or use_h_in = '0' then
                        -- New message: use H_INIT
                        new_stage0.hv(0) := H0_INIT;
                        new_stage0.hv(1) := H1_INIT;
                        new_stage0.hv(2) := H2_INIT;
                        new_stage0.hv(3) := H3_INIT;
                        new_stage0.hv(4) := H4_INIT;
                        new_stage0.hv(5) := H5_INIT;
                        new_stage0.hv(6) := H6_INIT;
                        new_stage0.hv(7) := H7_INIT;
                    else
                        -- Continuation: use provided hash state
                        new_stage0.hv(0) := h_in(511 downto 448);
                        new_stage0.hv(1) := h_in(447 downto 384);
                        new_stage0.hv(2) := h_in(383 downto 320);
                        new_stage0.hv(3) := h_in(319 downto 256);
                        new_stage0.hv(4) := h_in(255 downto 192);
                        new_stage0.hv(5) := h_in(191 downto 128);
                        new_stage0.hv(6) := h_in(127 downto 64);
                        new_stage0.hv(7) := h_in(63 downto 0);
                    end if;

                    -- Load message schedule from 1024-bit input
                    new_stage0.W(0)  := data_in(1023 downto 960);
                    new_stage0.W(1)  := data_in(959 downto 896);
                    new_stage0.W(2)  := data_in(895 downto 832);
                    new_stage0.W(3)  := data_in(831 downto 768);
                    new_stage0.W(4)  := data_in(767 downto 704);
                    new_stage0.W(5)  := data_in(703 downto 640);
                    new_stage0.W(6)  := data_in(639 downto 576);
                    new_stage0.W(7)  := data_in(575 downto 512);
                    new_stage0.W(8)  := data_in(511 downto 448);
                    new_stage0.W(9)  := data_in(447 downto 384);
                    new_stage0.W(10) := data_in(383 downto 320);
                    new_stage0.W(11) := data_in(319 downto 256);
                    new_stage0.W(12) := data_in(255 downto 192);
                    new_stage0.W(13) := data_in(191 downto 128);
                    new_stage0.W(14) := data_in(127 downto 64);
                    new_stage0.W(15) := data_in(63 downto 0);

                    -- Initialize working variables from hash
                    new_stage0.va := new_stage0.hv(0);
                    new_stage0.vb := new_stage0.hv(1);
                    new_stage0.vc := new_stage0.hv(2);
                    new_stage0.vd := new_stage0.hv(3);
                    new_stage0.ve := new_stage0.hv(4);
                    new_stage0.vf := new_stage0.hv(5);
                    new_stage0.vg := new_stage0.hv(6);
                    new_stage0.vh := new_stage0.hv(7);

                    -- Process rounds 0-7 inline
                    t := 0;
                    W_buf := new_stage0.W;

                    -- Get W values for rounds 0-7 (from message directly)
                    w0 := W_buf(0); w1 := W_buf(1); w2 := W_buf(2); w3 := W_buf(3);
                    w4 := W_buf(4); w5 := W_buf(5); w6 := W_buf(6); w7 := W_buf(7);

                    -- Compute K+W values
                    kw0 := add2(K(0), w0); kw1 := add2(K(1), w1);
                    kw2 := add2(K(2), w2); kw3 := add2(K(3), w3);
                    kw4 := add2(K(4), w4); kw5 := add2(K(5), w5);
                    kw6 := add2(K(6), w6); kw7 := add2(K(7), w7);

                    -- Load working variables
                    a := new_stage0.va; b := new_stage0.vb;
                    c := new_stage0.vc; d := new_stage0.vd;
                    e := new_stage0.ve; f := new_stage0.vf;
                    g := new_stage0.vg; h := new_stage0.vh;

                    -- 8 rounds inline
                    T1_0 := add4_csa(h, big_sigma1(e), ch(e, f, g), kw0);
                    T2_0 := add2(big_sigma0(a), maj(a, b, c));
                    a0 := add2(T1_0, T2_0); e0 := add2(d, T1_0);

                    T1_1 := add4_csa(g, big_sigma1(e0), ch(e0, e, f), kw1);
                    T2_1 := add2(big_sigma0(a0), maj(a0, a, b));
                    a1 := add2(T1_1, T2_1); e1 := add2(c, T1_1);

                    T1_2 := add4_csa(f, big_sigma1(e1), ch(e1, e0, e), kw2);
                    T2_2 := add2(big_sigma0(a1), maj(a1, a0, a));
                    a2 := add2(T1_2, T2_2); e2 := add2(b, T1_2);

                    T1_3 := add4_csa(e, big_sigma1(e2), ch(e2, e1, e0), kw3);
                    T2_3 := add2(big_sigma0(a2), maj(a2, a1, a0));
                    a3 := add2(T1_3, T2_3); e3 := add2(a, T1_3);

                    T1_4 := add4_csa(e0, big_sigma1(e3), ch(e3, e2, e1), kw4);
                    T2_4 := add2(big_sigma0(a3), maj(a3, a2, a1));
                    a4 := add2(T1_4, T2_4); e4 := add2(a0, T1_4);

                    T1_5 := add4_csa(e1, big_sigma1(e4), ch(e4, e3, e2), kw5);
                    T2_5 := add2(big_sigma0(a4), maj(a4, a3, a2));
                    a5 := add2(T1_5, T2_5); e5 := add2(a1, T1_5);

                    T1_6 := add4_csa(e2, big_sigma1(e5), ch(e5, e4, e3), kw6);
                    T2_6 := add2(big_sigma0(a5), maj(a5, a4, a3));
                    a6 := add2(T1_6, T2_6); e6 := add2(a2, T1_6);

                    T1_7 := add4_csa(e3, big_sigma1(e6), ch(e6, e5, e4), kw7);
                    T2_7 := add2(big_sigma0(a6), maj(a6, a5, a4));
                    a7 := add2(T1_7, T2_7); e7 := add2(a3, T1_7);

                    -- Store result to stage 0
                    stages(0).valid <= '1';
                    stages(0).last <= new_stage0.last;
                    stages(0).hv <= new_stage0.hv;
                    stages(0).va <= a7; stages(0).vb <= a6;
                    stages(0).vc <= a5; stages(0).vd <= a4;
                    stages(0).ve <= e7; stages(0).vf <= e6;
                    stages(0).vg <= e5; stages(0).vh <= e4;
                    stages(0).W <= W_buf;
                else
                    stages(0) <= STAGE_INIT;
                end if;

                ---------------------------------------------------------
                -- Stages 1-9: Process 8 rounds each
                ---------------------------------------------------------
                for i in 1 to 9 loop
                    if stages(i-1).valid = '1' then
                        t := i * 8;
                        stage_in := stages(i-1);
                        W_buf := stage_in.W;

                        -- Get/compute W values
                        if t < 16 then
                            -- Rounds 8-15: from message
                            w0 := W_buf(w_idx(t));   w1 := W_buf(w_idx(t+1));
                            w2 := W_buf(w_idx(t+2)); w3 := W_buf(w_idx(t+3));
                            w4 := W_buf(w_idx(t+4)); w5 := W_buf(w_idx(t+5));
                            w6 := W_buf(w_idx(t+6)); w7 := W_buf(w_idx(t+7));
                        else
                            -- Rounds 16+: compute W schedule
                            -- SIDE-CHANNEL NOTE (SCA-02): Cascading W dependencies within
                            -- single cycle create power correlation. See SECURITY.md.
                            w0 := std_logic_vector(
                                unsigned(small_sigma1(W_buf(w_idx(t-2)))) +
                                unsigned(W_buf(w_idx(t-7))) +
                                unsigned(small_sigma0(W_buf(w_idx(t-15)))) +
                                unsigned(W_buf(w_idx(t-16))));
                            w1 := std_logic_vector(
                                unsigned(small_sigma1(W_buf(w_idx(t-1)))) +
                                unsigned(W_buf(w_idx(t-6))) +
                                unsigned(small_sigma0(W_buf(w_idx(t-14)))) +
                                unsigned(W_buf(w_idx(t-15))));
                            w2 := std_logic_vector(
                                unsigned(small_sigma1(w0)) +
                                unsigned(W_buf(w_idx(t-5))) +
                                unsigned(small_sigma0(W_buf(w_idx(t-13)))) +
                                unsigned(W_buf(w_idx(t-14))));
                            w3 := std_logic_vector(
                                unsigned(small_sigma1(w1)) +
                                unsigned(W_buf(w_idx(t-4))) +
                                unsigned(small_sigma0(W_buf(w_idx(t-12)))) +
                                unsigned(W_buf(w_idx(t-13))));
                            w4 := std_logic_vector(
                                unsigned(small_sigma1(w2)) +
                                unsigned(W_buf(w_idx(t-3))) +
                                unsigned(small_sigma0(W_buf(w_idx(t-11)))) +
                                unsigned(W_buf(w_idx(t-12))));
                            w5 := std_logic_vector(
                                unsigned(small_sigma1(w3)) +
                                unsigned(W_buf(w_idx(t-2))) +
                                unsigned(small_sigma0(W_buf(w_idx(t-10)))) +
                                unsigned(W_buf(w_idx(t-11))));
                            w6 := std_logic_vector(
                                unsigned(small_sigma1(w4)) +
                                unsigned(W_buf(w_idx(t-1))) +
                                unsigned(small_sigma0(W_buf(w_idx(t-9)))) +
                                unsigned(W_buf(w_idx(t-10))));
                            w7 := std_logic_vector(
                                unsigned(small_sigma1(w5)) +
                                unsigned(w0) +
                                unsigned(small_sigma0(W_buf(w_idx(t-8)))) +
                                unsigned(W_buf(w_idx(t-9))));

                            -- Update W buffer
                            W_buf(w_idx(t))   := w0; W_buf(w_idx(t+1)) := w1;
                            W_buf(w_idx(t+2)) := w2; W_buf(w_idx(t+3)) := w3;
                            W_buf(w_idx(t+4)) := w4; W_buf(w_idx(t+5)) := w5;
                            W_buf(w_idx(t+6)) := w6; W_buf(w_idx(t+7)) := w7;
                        end if;

                        -- Compute K+W
                        kw0 := add2(K(t), w0);   kw1 := add2(K(t+1), w1);
                        kw2 := add2(K(t+2), w2); kw3 := add2(K(t+3), w3);
                        kw4 := add2(K(t+4), w4); kw5 := add2(K(t+5), w5);
                        kw6 := add2(K(t+6), w6); kw7 := add2(K(t+7), w7);

                        -- Load working variables
                        a := stage_in.va; b := stage_in.vb;
                        c := stage_in.vc; d := stage_in.vd;
                        e := stage_in.ve; f := stage_in.vf;
                        g := stage_in.vg; h := stage_in.vh;

                        -- 8 rounds
                        T1_0 := add4_csa(h, big_sigma1(e), ch(e, f, g), kw0);
                        T2_0 := add2(big_sigma0(a), maj(a, b, c));
                        a0 := add2(T1_0, T2_0); e0 := add2(d, T1_0);

                        T1_1 := add4_csa(g, big_sigma1(e0), ch(e0, e, f), kw1);
                        T2_1 := add2(big_sigma0(a0), maj(a0, a, b));
                        a1 := add2(T1_1, T2_1); e1 := add2(c, T1_1);

                        T1_2 := add4_csa(f, big_sigma1(e1), ch(e1, e0, e), kw2);
                        T2_2 := add2(big_sigma0(a1), maj(a1, a0, a));
                        a2 := add2(T1_2, T2_2); e2 := add2(b, T1_2);

                        T1_3 := add4_csa(e, big_sigma1(e2), ch(e2, e1, e0), kw3);
                        T2_3 := add2(big_sigma0(a2), maj(a2, a1, a0));
                        a3 := add2(T1_3, T2_3); e3 := add2(a, T1_3);

                        T1_4 := add4_csa(e0, big_sigma1(e3), ch(e3, e2, e1), kw4);
                        T2_4 := add2(big_sigma0(a3), maj(a3, a2, a1));
                        a4 := add2(T1_4, T2_4); e4 := add2(a0, T1_4);

                        T1_5 := add4_csa(e1, big_sigma1(e4), ch(e4, e3, e2), kw5);
                        T2_5 := add2(big_sigma0(a4), maj(a4, a3, a2));
                        a5 := add2(T1_5, T2_5); e5 := add2(a1, T1_5);

                        T1_6 := add4_csa(e2, big_sigma1(e5), ch(e5, e4, e3), kw6);
                        T2_6 := add2(big_sigma0(a5), maj(a5, a4, a3));
                        a6 := add2(T1_6, T2_6); e6 := add2(a2, T1_6);

                        T1_7 := add4_csa(e3, big_sigma1(e6), ch(e6, e5, e4), kw7);
                        T2_7 := add2(big_sigma0(a6), maj(a6, a5, a4));
                        a7 := add2(T1_7, T2_7); e7 := add2(a3, T1_7);

                        -- Store to next stage
                        stages(i).valid <= '1';
                        stages(i).last <= stage_in.last;
                        stages(i).hv <= stage_in.hv;
                        stages(i).va <= a7; stages(i).vb <= a6;
                        stages(i).vc <= a5; stages(i).vd <= a4;
                        stages(i).ve <= e7; stages(i).vf <= e6;
                        stages(i).vg <= e5; stages(i).vh <= e4;
                        stages(i).W <= W_buf;
                    else
                        stages(i) <= STAGE_INIT;
                    end if;
                end loop;

                ---------------------------------------------------------
                -- Output: Finalize hash after stage 9
                ---------------------------------------------------------
                if stages(9).valid = '1' then
                    -- Compute final hash values: H + working variables
                    final_hv(0) := std_logic_vector(unsigned(stages(9).hv(0)) + unsigned(stages(9).va));
                    final_hv(1) := std_logic_vector(unsigned(stages(9).hv(1)) + unsigned(stages(9).vb));
                    final_hv(2) := std_logic_vector(unsigned(stages(9).hv(2)) + unsigned(stages(9).vc));
                    final_hv(3) := std_logic_vector(unsigned(stages(9).hv(3)) + unsigned(stages(9).vd));
                    final_hv(4) := std_logic_vector(unsigned(stages(9).hv(4)) + unsigned(stages(9).ve));
                    final_hv(5) := std_logic_vector(unsigned(stages(9).hv(5)) + unsigned(stages(9).vf));
                    final_hv(6) := std_logic_vector(unsigned(stages(9).hv(6)) + unsigned(stages(9).vg));
                    final_hv(7) := std_logic_vector(unsigned(stages(9).hv(7)) + unsigned(stages(9).vh));

                    -- Always output updated hash state (for multi-block)
                    h_out <= final_hv(0) & final_hv(1) & final_hv(2) & final_hv(3) &
                             final_hv(4) & final_hv(5) & final_hv(6) & final_hv(7);
                    h_out_valid <= '1';

                    -- Output final hash only on last block
                    if stages(9).last = '1' then
                        hash_out <= final_hv(0) & final_hv(1) & final_hv(2) &
                                    final_hv(3) & final_hv(4) & final_hv(5);
                        hash_valid <= '1';
                    end if;
                end if;

            end if;
        end if;
    end process;

end architecture rtl;
