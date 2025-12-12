-- SHA-384 Implementation using Formally Verified Round Function
-- Uses sha384_round.vhd component which has been verified with SAW
--
-- Same interface as sha384.vhd baseline for compatibility with test suite

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha384_pkg.all;

entity sha384_verified is
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        start       : in  std_logic;
        data_in     : in  std_logic_vector(63 downto 0);
        data_valid  : in  std_logic;
        last_block  : in  std_logic;
        ready       : out std_logic;
        hash_out    : out std_logic_vector(383 downto 0);
        hash_valid  : out std_logic
    );
end entity sha384_verified;

architecture rtl of sha384_verified is

    -- Instantiate the formally verified round function
    component sha384_round is
        port (
            a_in, b_in, c_in, d_in : in std_logic_vector(63 downto 0);
            e_in, f_in, g_in, h_in : in std_logic_vector(63 downto 0);
            k : in std_logic_vector(63 downto 0);
            w : in std_logic_vector(63 downto 0);
            a_out, b_out, c_out, d_out : out std_logic_vector(63 downto 0);
            e_out, f_out, g_out, h_out : out std_logic_vector(63 downto 0)
        );
    end component;

    type state_type is (IDLE, LOAD_BLOCK, COMPRESS, UPDATE_HASH, DONE);
    signal state : state_type := IDLE;

    -- Hash values
    signal hv : word64_array(0 to 7);

    -- Working variables (active)
    signal va, vb, vc, vd, ve, vf, vg, vh : word64;

    -- Round function outputs
    signal va_next, vb_next, vc_next, vd_next : word64;
    signal ve_next, vf_next, vg_next, vh_next : word64;

    -- Message schedule
    signal W : word64_array(0 to 15);

    -- Counters
    signal word_count : unsigned(3 downto 0) := (others => '0');
    signal round : unsigned(6 downto 0) := (others => '0');

    -- Control
    signal is_last_block : std_logic := '0';

    -- Current K and W values for round function
    signal k_val, w_val : word64;

begin

    -- Instantiate the formally verified round function
    round_fn: sha384_round
        port map (
            a_in => va, b_in => vb, c_in => vc, d_in => vd,
            e_in => ve, f_in => vf, g_in => vg, h_in => vh,
            k => k_val,
            w => w_val,
            a_out => va_next, b_out => vb_next, c_out => vc_next, d_out => vd_next,
            e_out => ve_next, f_out => vf_next, g_out => vg_next, h_out => vh_next
        );

    -- Get current K value
    k_val <= K(to_integer(round));

    -- Get current W value (from buffer for rounds 0-15, computed for 16-79)
    process(round, W)
        variable w_new : word64;
    begin
        if round < 16 then
            w_val <= W(to_integer(round(3 downto 0)));
        else
            -- W[t] = sigma1(W[t-2]) + W[t-7] + sigma0(W[t-15]) + W[t-16]
            w_new := std_logic_vector(
                unsigned(small_sigma1(W(14))) +
                unsigned(W(9)) +
                unsigned(small_sigma0(W(1))) +
                unsigned(W(0))
            );
            w_val <= w_new;
        end if;
    end process;

    -- Main state machine
    process(clk)
        variable w_new : word64;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                word_count <= (others => '0');
                round <= (others => '0');
                hash_valid <= '0';
                ready <= '1';
                is_last_block <= '0';

                -- Initialize hash values
                hv(0) <= H0_INIT; hv(1) <= H1_INIT;
                hv(2) <= H2_INIT; hv(3) <= H3_INIT;
                hv(4) <= H4_INIT; hv(5) <= H5_INIT;
                hv(6) <= H6_INIT; hv(7) <= H7_INIT;
            else
                case state is
                    when IDLE =>
                        hash_valid <= '0';
                        ready <= '1';
                        if start = '1' then
                            -- Initialize hash values for new message
                            hv(0) <= H0_INIT; hv(1) <= H1_INIT;
                            hv(2) <= H2_INIT; hv(3) <= H3_INIT;
                            hv(4) <= H4_INIT; hv(5) <= H5_INIT;
                            hv(6) <= H6_INIT; hv(7) <= H7_INIT;
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
                                round <= (others => '0');
                                ready <= '0';

                                -- Initialize working variables
                                va <= hv(0); vb <= hv(1);
                                vc <= hv(2); vd <= hv(3);
                                ve <= hv(4); vf <= hv(5);
                                vg <= hv(6); vh <= hv(7);

                                state <= COMPRESS;
                            else
                                word_count <= word_count + 1;
                            end if;
                        end if;

                    when COMPRESS =>
                        ready <= '0';

                        -- Update working variables from round function output
                        va <= va_next;
                        vb <= vb_next;
                        vc <= vc_next;
                        vd <= vd_next;
                        ve <= ve_next;
                        vf <= vf_next;
                        vg <= vg_next;
                        vh <= vh_next;

                        -- Update W array for rounds >= 16
                        -- Shift happens AFTER w_val is used (for next round)
                        if round >= 16 then
                            -- Shift W array
                            for i in 0 to 14 loop
                                W(i) <= W(i+1);
                            end loop;
                            -- Compute new W value for future rounds
                            w_new := std_logic_vector(
                                unsigned(small_sigma1(W(14))) +
                                unsigned(W(9)) +
                                unsigned(small_sigma0(W(1))) +
                                unsigned(W(0))
                            );
                            W(15) <= w_new;
                        end if;

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
                        ready <= '1';
                        if start = '1' then
                            hash_valid <= '0';
                            -- Initialize hash values for new message
                            hv(0) <= H0_INIT; hv(1) <= H1_INIT;
                            hv(2) <= H2_INIT; hv(3) <= H3_INIT;
                            hv(4) <= H4_INIT; hv(5) <= H5_INIT;
                            hv(6) <= H6_INIT; hv(7) <= H7_INIT;
                            word_count <= (others => '0');
                            state <= LOAD_BLOCK;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- Output hash (first 384 bits = 6 words)
    hash_out <= hv(0) & hv(1) & hv(2) & hv(3) & hv(4) & hv(5);

end architecture rtl;
