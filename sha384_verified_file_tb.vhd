-- Testbench for SHA-384 Verified Implementation
-- Uses the same file-based test vectors as other implementations

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity sha384_verified_file_tb is
end entity sha384_verified_file_tb;

architecture tb of sha384_verified_file_tb is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal start : std_logic := '0';
    signal data_in : std_logic_vector(63 downto 0) := (others => '0');
    signal data_valid : std_logic := '0';
    signal last_block : std_logic := '0';
    signal ready : std_logic;
    signal hash_out : std_logic_vector(383 downto 0);
    signal hash_valid : std_logic;

    constant CLK_PERIOD : time := 10 ns;
    signal test_done : boolean := false;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD/2 when not test_done else '0';

    -- Unit under test
    uut: entity work.sha384_verified
        port map (
            clk => clk,
            reset => reset,
            start => start,
            data_in => data_in,
            data_valid => data_valid,
            last_block => last_block,
            ready => ready,
            hash_out => hash_out,
            hash_valid => hash_valid
        );

    -- Test process
    test_proc: process
        file test_file : text;
        variable line_buf : line;
        variable num_tests : integer;
        variable num_blocks : integer;
        variable word_val : std_logic_vector(63 downto 0);
        variable expected_hash : std_logic_vector(383 downto 0);
        variable test_passed : boolean;
        variable pass_count : integer := 0;
        variable fail_count : integer := 0;
    begin
        -- Reset
        reset <= '1';
        wait for CLK_PERIOD * 2;
        reset <= '0';
        wait for CLK_PERIOD * 2;

        -- Open test vectors file
        file_open(test_file, "test_vectors.txt", read_mode);

        -- Read number of tests
        readline(test_file, line_buf);
        read(line_buf, num_tests);

        report "Running " & integer'image(num_tests) & " tests on sha384_verified...";

        -- Run each test
        for t in 0 to num_tests - 1 loop
            -- Read number of blocks
            readline(test_file, line_buf);
            read(line_buf, num_blocks);

            -- Start new hash
            wait until rising_edge(clk);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            -- Process each block
            for b in 0 to num_blocks - 1 loop
                -- Wait for ready
                wait until ready = '1' and rising_edge(clk);

                -- Send 16 words
                for w in 0 to 15 loop
                    readline(test_file, line_buf);
                    hread(line_buf, word_val);

                    data_in <= word_val;
                    data_valid <= '1';
                    if b = num_blocks - 1 and w = 15 then
                        last_block <= '1';
                    else
                        last_block <= '0';
                    end if;
                    wait until rising_edge(clk);
                end loop;
                data_valid <= '0';
            end loop;

            -- Wait for hash
            wait until hash_valid = '1' and rising_edge(clk);

            -- Read expected hash (6 words)
            expected_hash := (others => '0');
            for w in 0 to 5 loop
                readline(test_file, line_buf);
                hread(line_buf, word_val);
                expected_hash(383 - w*64 downto 320 - w*64) := word_val;
            end loop;

            -- Compare
            test_passed := (hash_out = expected_hash);
            if test_passed then
                pass_count := pass_count + 1;
            else
                fail_count := fail_count + 1;
                report "Test " & integer'image(t) & " FAILED!" severity warning;
                report "Expected: " & to_hstring(expected_hash);
                report "Got:      " & to_hstring(hash_out);
            end if;

            wait for CLK_PERIOD;
        end loop;

        file_close(test_file);

        report "sha384_verified: " & integer'image(pass_count) & "/" &
               integer'image(num_tests) & " tests passed";

        if fail_count > 0 then
            report "SOME TESTS FAILED!" severity failure;
        end if;

        test_done <= true;
        wait;
    end process;

end architecture tb;
