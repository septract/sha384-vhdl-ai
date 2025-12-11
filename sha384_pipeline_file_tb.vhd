-------------------------------------------------------------------------------
-- SHA-384 Pipeline File-based Testbench
-- Reads test vectors from test_vectors.txt (1024-bit interface)
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

use work.sha384_fast_pkg.all;

entity sha384_pipeline_file_tb is
end entity sha384_pipeline_file_tb;

architecture test of sha384_pipeline_file_tb is
    constant CLK_PERIOD : time := 10 ns;

    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal start       : std_logic := '0';
    signal data_in     : std_logic_vector(1023 downto 0) := (others => '0');
    signal data_valid  : std_logic := '0';
    signal last_block  : std_logic := '0';
    signal ready       : std_logic;
    signal h_in        : std_logic_vector(511 downto 0) := (others => '0');
    signal use_h_in    : std_logic := '0';
    signal hash_out    : std_logic_vector(383 downto 0);
    signal hash_valid  : std_logic;
    signal h_out       : std_logic_vector(511 downto 0);
    signal h_out_valid : std_logic;
    signal test_done   : boolean := false;

    -- Convert hex character to 4-bit value
    function hex_to_slv4(c : character) return std_logic_vector is
    begin
        case c is
            when '0' => return "0000"; when '1' => return "0001";
            when '2' => return "0010"; when '3' => return "0011";
            when '4' => return "0100"; when '5' => return "0101";
            when '6' => return "0110"; when '7' => return "0111";
            when '8' => return "1000"; when '9' => return "1001";
            when 'a'|'A' => return "1010"; when 'b'|'B' => return "1011";
            when 'c'|'C' => return "1100"; when 'd'|'D' => return "1101";
            when 'e'|'E' => return "1110"; when 'f'|'F' => return "1111";
            when others => return "0000";
        end case;
    end function;

    -- Convert 16-char hex string to 64-bit word
    function hex_to_word64(s : string) return std_logic_vector is
        variable result : std_logic_vector(63 downto 0);
    begin
        for i in 1 to 16 loop
            result(67 - i*4 downto 64 - i*4) := hex_to_slv4(s(i));
        end loop;
        return result;
    end function;

begin
    clk <= not clk after CLK_PERIOD/2 when not test_done else '0';

    uut: entity work.sha384_pipeline
        port map (
            clk        => clk,
            reset      => reset,
            start      => start,
            data_in    => data_in,
            data_valid => data_valid,
            last_block => last_block,
            ready      => ready,
            h_in       => h_in,
            use_h_in   => use_h_in,
            hash_out   => hash_out,
            hash_valid => hash_valid,
            h_out      => h_out,
            h_out_valid=> h_out_valid
        );

    process
        file vectors_file : text;
        variable line_buf : line;
        variable num_tests : integer;
        variable num_blocks : integer;
        variable word_str : string(1 to 16);
        variable words : word64_array(0 to 15);
        variable expected_hash : std_logic_vector(383 downto 0);
        variable current_h : std_logic_vector(511 downto 0);
        variable pass_count : integer := 0;
        variable fail_count : integer := 0;
        variable cycle_count : integer := 0;
        variable start_cycle : integer := 0;
    begin
        -- Reset
        reset <= '1';
        wait for CLK_PERIOD * 2;
        reset <= '0';
        wait for CLK_PERIOD * 2;

        -- Open test vectors file
        file_open(vectors_file, "test_vectors.txt", read_mode);

        -- Read number of tests
        readline(vectors_file, line_buf);
        read(line_buf, num_tests);

        report "Running " & integer'image(num_tests) & " tests (pipelined)";

        -- Process each test
        for test_idx in 0 to num_tests - 1 loop
            -- Read number of blocks
            readline(vectors_file, line_buf);
            read(line_buf, num_blocks);

            report "Test " & integer'image(test_idx) & ": " & integer'image(num_blocks) & " block(s)";

            start_cycle := cycle_count;

            -- Process each block
            for block_idx in 0 to num_blocks - 1 loop
                -- Read 16 words for this block
                for w in 0 to 15 loop
                    readline(vectors_file, line_buf);
                    read(line_buf, word_str);
                    words(w) := hex_to_word64(word_str);
                end loop;

                -- Wait for ready
                wait until rising_edge(clk) and ready = '1';
                cycle_count := cycle_count + 1;

                -- Send full 1024-bit block
                data_in <= words(0) & words(1) & words(2) & words(3) &
                           words(4) & words(5) & words(6) & words(7) &
                           words(8) & words(9) & words(10) & words(11) &
                           words(12) & words(13) & words(14) & words(15);
                data_valid <= '1';

                -- Set start for first block
                if block_idx = 0 then
                    start <= '1';
                    use_h_in <= '0';
                else
                    -- Continuation block: use previous h_out
                    start <= '0';
                    use_h_in <= '1';
                    h_in <= current_h;
                end if;

                -- Set last_block flag
                if block_idx = num_blocks - 1 then
                    last_block <= '1';
                else
                    last_block <= '0';
                end if;

                wait until rising_edge(clk);
                cycle_count := cycle_count + 1;
                data_valid <= '0';
                start <= '0';
                last_block <= '0';
                use_h_in <= '0';

                -- For multi-block: wait for intermediate h_out
                if block_idx < num_blocks - 1 then
                    -- Wait for h_out_valid for this block
                    while h_out_valid = '0' loop
                        wait until rising_edge(clk);
                        cycle_count := cycle_count + 1;
                    end loop;
                    current_h := h_out;
                    wait until rising_edge(clk);
                    cycle_count := cycle_count + 1;
                end if;
            end loop;

            -- Read expected hash (6 words)
            for w in 0 to 5 loop
                readline(vectors_file, line_buf);
                read(line_buf, word_str);
                expected_hash(383 - w*64 downto 320 - w*64) := hex_to_word64(word_str);
            end loop;

            -- Wait for final result
            while hash_valid = '0' loop
                wait until rising_edge(clk);
                cycle_count := cycle_count + 1;
            end loop;
            wait until rising_edge(clk);
            cycle_count := cycle_count + 1;

            -- Output hash for Python to parse
            report "Hash: " & to_hstring(hash_out);
            report "  Cycles: " & integer'image(cycle_count - start_cycle);

            -- Check result
            if hash_out = expected_hash then
                report "  PASS";
                pass_count := pass_count + 1;
            else
                report "  FAIL" severity error;
                report "    Expected: " & to_hstring(expected_hash);
                fail_count := fail_count + 1;
            end if;
        end loop;

        file_close(vectors_file);

        report "========================================";
        report "Results: " & integer'image(pass_count) & "/" & integer'image(num_tests) & " passed";
        report "Total cycles: " & integer'image(cycle_count);
        report "========================================";

        test_done <= true;
        wait;
    end process;

end architecture test;
