-------------------------------------------------------------------------------
-- SHA-384 Core
-- Implements SHA-384 hash algorithm
--
-- Interface:
--   clk        : Clock input
--   reset      : Synchronous reset (active high)
--   start      : Start hashing a new message
--   data_in    : 64-bit input data word
--   data_valid : Input data is valid
--   last_block : This is the last block (message already padded)
--   ready      : Core is ready to accept data
--   hash_out   : 384-bit hash output
--   hash_valid : Hash output is valid
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity sha384 is
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        start      : in  std_logic;
        data_in    : in  std_logic_vector(63 downto 0);
        data_valid : in  std_logic;
        last_block : in  std_logic;
        ready      : out std_logic;
        hash_out   : out std_logic_vector(383 downto 0);
        hash_valid : out std_logic
    );
end entity sha384;

architecture rtl of sha384 is

    -- State machine states
    type state_type is (IDLE, LOAD_BLOCK, COMPRESS, UPDATE_HASH, DONE);
    signal state : state_type;

    -- Hash values (H0-H7), only H0-H5 used for output
    signal hv : word64_array(0 to 7);

    -- Working variables (as signals for state retention between rounds)
    signal va, vb, vc, vd, ve, vf, vg, vh : word64;

    -- Message schedule array W (circular buffer of 16 words)
    signal W : word64_array(0 to 15);

    -- Counters
    signal word_count : unsigned(3 downto 0);  -- 0-15 for loading 16 words
    signal round      : unsigned(6 downto 0);  -- 0-79 for 80 rounds

    -- Flag for last block
    signal is_last_block : std_logic;

begin

    -- Main process
    process(clk)
        variable w_val   : word64;  -- Current W value for round
        variable w_new   : word64;  -- New computed W value
        variable T1, T2  : word64;  -- Temporary values
        variable new_a, new_e : word64;  -- New working variable values
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state        <= IDLE;
                hash_valid   <= '0';
                ready        <= '1';
                word_count   <= (others => '0');
                round        <= (others => '0');
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
                            W(to_integer(word_count)) <= data_in;
                            is_last_block <= last_block;

                            if word_count = 15 then
                                word_count <= (others => '0');
                                round      <= (others => '0');
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
                            else
                                word_count <= word_count + 1;
                            end if;
                        end if;

                    when COMPRESS =>
                        -- Get/compute W value for this round
                        if round < 16 then
                            -- First 16 rounds: use message words directly
                            w_val := W(to_integer(round(3 downto 0)));
                        else
                            -- Rounds 16-79: compute new W value
                            -- W[t] = sigma1(W[t-2]) + W[t-7] + sigma0(W[t-15]) + W[t-16]
                            -- With circular buffer: W[14]=W[t-2], W[9]=W[t-7], W[1]=W[t-15], W[0]=W[t-16]
                            w_new := std_logic_vector(
                                unsigned(small_sigma1(W(14))) +
                                unsigned(W(9)) +
                                unsigned(small_sigma0(W(1))) +
                                unsigned(W(0))
                            );
                            w_val := w_new;

                            -- Shift W array and insert new value
                            for i in 0 to 14 loop
                                W(i) <= W(i+1);
                            end loop;
                            W(15) <= w_new;
                        end if;

                        -- Compute T1 = h + Sigma1(e) + Ch(e,f,g) + K[t] + W[t]
                        T1 := std_logic_vector(
                            unsigned(vh) +
                            unsigned(big_sigma1(ve)) +
                            unsigned(ch(ve, vf, vg)) +
                            unsigned(K(to_integer(round))) +
                            unsigned(w_val)
                        );

                        -- Compute T2 = Sigma0(a) + Maj(a,b,c)
                        T2 := std_logic_vector(
                            unsigned(big_sigma0(va)) +
                            unsigned(maj(va, vb, vc))
                        );

                        -- Compute new values
                        new_a := std_logic_vector(unsigned(T1) + unsigned(T2));
                        new_e := std_logic_vector(unsigned(vd) + unsigned(T1));

                        -- Update working variables: h=g, g=f, f=e, e=d+T1, d=c, c=b, b=a, a=T1+T2
                        vh <= vg;
                        vg <= vf;
                        vf <= ve;
                        ve <= new_e;
                        vd <= vc;
                        vc <= vb;
                        vb <= va;
                        va <= new_a;

                        if round = 79 then
                            state <= UPDATE_HASH;
                        else
                            round <= round + 1;
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
