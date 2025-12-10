-------------------------------------------------------------------------------
-- SHA-384 Testbench
-- Tests SHA-384 implementation using NIST test vectors
-- Source: https://www.di-mgt.com.au/sha_testvectors.html
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_pkg.all;

entity sha384_tb is
end entity sha384_tb;

architecture sim of sha384_tb is

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

    -- Signals
    signal clk        : std_logic := '0';
    signal reset      : std_logic := '1';
    signal start      : std_logic := '0';
    signal data_in    : std_logic_vector(63 downto 0) := (others => '0');
    signal data_valid : std_logic := '0';
    signal last_block : std_logic := '0';
    signal ready      : std_logic;
    signal hash_out   : std_logic_vector(383 downto 0);
    signal hash_valid : std_logic;

    -- Test control
    signal test_done  : boolean := false;
    signal test_count : integer := 0;
    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

    -- Helper function to convert hex character to std_logic_vector
    function hex_char_to_slv(c : character) return std_logic_vector is
    begin
        case c is
            when '0' => return "0000";
            when '1' => return "0001";
            when '2' => return "0010";
            when '3' => return "0011";
            when '4' => return "0100";
            when '5' => return "0101";
            when '6' => return "0110";
            when '7' => return "0111";
            when '8' => return "1000";
            when '9' => return "1001";
            when 'a' | 'A' => return "1010";
            when 'b' | 'B' => return "1011";
            when 'c' | 'C' => return "1100";
            when 'd' | 'D' => return "1101";
            when 'e' | 'E' => return "1110";
            when 'f' | 'F' => return "1111";
            when others => return "0000";
        end case;
    end function;

    -- Helper function to convert 16-char hex string to 64-bit word
    function hex_to_word64(hex : string(1 to 16)) return std_logic_vector is
        variable result : std_logic_vector(63 downto 0);
    begin
        for i in 1 to 16 loop
            result(67 - i*4 downto 64 - i*4) := hex_char_to_slv(hex(i));
        end loop;
        return result;
    end function;

    -- Helper function to convert 96-char hex string to 384-bit hash
    function hex_to_hash384(hex : string(1 to 96)) return std_logic_vector is
        variable result : std_logic_vector(383 downto 0);
    begin
        for i in 1 to 96 loop
            result(387 - i*4 downto 384 - i*4) := hex_char_to_slv(hex(i));
        end loop;
        return result;
    end function;

    -- Procedure to send a 1024-bit block (16 x 64-bit words)
    procedure send_block(
        signal clk_sig    : in  std_logic;
        signal data_sig   : out std_logic_vector(63 downto 0);
        signal valid_sig  : out std_logic;
        signal last_sig   : out std_logic;
        signal ready_sig  : in  std_logic;
        constant words    : in  word64_array(0 to 15);
        constant is_last  : in  boolean
    ) is
    begin
        for i in 0 to 15 loop
            wait until rising_edge(clk_sig) and ready_sig = '1';
            data_sig  <= words(i);
            valid_sig <= '1';
            if i = 15 and is_last then
                last_sig <= '1';
            else
                last_sig <= '0';
            end if;
            wait until rising_edge(clk_sig);
            valid_sig <= '0';
            last_sig  <= '0';
        end loop;
    end procedure;

begin

    -- Instantiate DUT
    dut: entity work.sha384
        port map (
            clk        => clk,
            reset      => reset,
            start      => start,
            data_in    => data_in,
            data_valid => data_valid,
            last_block => last_block,
            ready      => ready,
            hash_out   => hash_out,
            hash_valid => hash_valid
        );

    -- Clock generation
    clk_proc: process
    begin
        while not test_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Test stimulus
    stim_proc: process
        -- Test vector 1: "abc" (padded to 1024 bits)
        -- Message: 0x6162638000...00 + 128-bit length (24 = 0x18)
        constant tv1_block : word64_array(0 to 15) := (
            x"6162638000000000",  -- 'abc' + padding start
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
            x"0000000000000000",  -- High 64 bits of length
            x"0000000000000018"   -- Low 64 bits of length (24 bits)
        );
        constant tv1_expected : std_logic_vector(383 downto 0) :=
            hex_to_hash384("cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7");

        -- Test vector 2: empty string "" (padded)
        -- Message: 0x8000...00 + 128-bit length (0)
        constant tv2_block : word64_array(0 to 15) := (
            x"8000000000000000",  -- padding start
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
            x"0000000000000000"   -- Length = 0
        );
        constant tv2_expected : std_logic_vector(383 downto 0) :=
            hex_to_hash384("38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b");

        -- Test vector 3: "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" (56 bytes = 448 bits)
        -- Needs padding to 1024 bits
        constant tv3_block : word64_array(0 to 15) := (
            x"6162636462636465",  -- "abcdbcde"
            x"6364656664656667",  -- "cdefdefg"
            x"6566676866676869",  -- "efghfghi"
            x"6768696a68696a6b",  -- "ghijhijk"
            x"696a6b6c6a6b6c6d",  -- "ijkljklm"
            x"6b6c6d6e6c6d6e6f",  -- "klmnlmno"
            x"6d6e6f706e6f7071",  -- "mnopnopq"
            x"8000000000000000",  -- padding start
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"0000000000000000",
            x"00000000000001c0"   -- Length = 448 bits
        );
        constant tv3_expected : std_logic_vector(383 downto 0) :=
            hex_to_hash384("3391fdddfc8dc7393707a65b1b4709397cf8b1d162af05abfe8f450de5f36bc6b0455a8520bc4e6f5fe95b1fe3c8452b");

        -- Test vector 4: 112 bytes = 896 bits (requires TWO 1024-bit blocks)
        -- "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
        -- Block 1: message (14 words) + padding start + zero
        constant tv4_block1 : word64_array(0 to 15) := (
            x"6162636465666768",  -- "abcdefgh"
            x"6263646566676869",  -- "bcdefghi"
            x"636465666768696a",  -- "cdefghij"
            x"6465666768696a6b",  -- "defghijk"
            x"65666768696a6b6c",  -- "efghijkl"
            x"666768696a6b6c6d",  -- "fghijklm"
            x"6768696a6b6c6d6e",  -- "ghijklmn"
            x"68696a6b6c6d6e6f",  -- "hijklmno"
            x"696a6b6c6d6e6f70",  -- "ijklmnop"
            x"6a6b6c6d6e6f7071",  -- "jklmnopq"
            x"6b6c6d6e6f707172",  -- "klmnopqr"
            x"6c6d6e6f70717273",  -- "lmnopqrs"
            x"6d6e6f7071727374",  -- "mnopqrst"
            x"6e6f707172737475",  -- "nopqrstu"
            x"8000000000000000",  -- padding start
            x"0000000000000000"   -- zeros
        );
        -- Block 2: zeros + 128-bit length (896 = 0x380)
        constant tv4_block2 : word64_array(0 to 15) := (
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
            x"0000000000000000",  -- High 64 bits of length
            x"0000000000000380"   -- Low 64 bits of length (896 bits)
        );
        constant tv4_expected : std_logic_vector(383 downto 0) :=
            hex_to_hash384("09330c33f71147e83d192fc782cd1b4753111b173b3b05d22fa08086e3b0f712fcc7c71a557e2db966c3e9fa91746039");

        variable hash_match : boolean;

    begin
        -- Initial reset
        reset <= '1';
        wait for CLK_PERIOD * 5;
        reset <= '0';
        wait for CLK_PERIOD * 2;

        report "========================================";
        report "SHA-384 Test Suite Starting";
        report "========================================";

        ------------------------------------------------------------------------
        -- Test 1: "abc"
        ------------------------------------------------------------------------
        test_count <= test_count + 1;
        report "Test 1: SHA-384(""abc"")";

        wait until rising_edge(clk) and ready = '1';
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        send_block(clk, data_in, data_valid, last_block, ready, tv1_block, true);

        wait until rising_edge(clk) and hash_valid = '1';
        wait for 1 ns;

        hash_match := (hash_out = tv1_expected);
        if hash_match then
            report "  PASSED";
            pass_count <= pass_count + 1;
        else
            report "  FAILED" severity error;
            report "  Expected: cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7";
            report "  Got:      " & to_hstring(hash_out);
            fail_count <= fail_count + 1;
        end if;

        wait for CLK_PERIOD * 5;

        ------------------------------------------------------------------------
        -- Test 2: "" (empty string)
        ------------------------------------------------------------------------
        test_count <= test_count + 1;
        report "Test 2: SHA-384("""")";

        wait until rising_edge(clk) and ready = '1';
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        send_block(clk, data_in, data_valid, last_block, ready, tv2_block, true);

        wait until rising_edge(clk) and hash_valid = '1';
        wait for 1 ns;

        hash_match := (hash_out = tv2_expected);
        if hash_match then
            report "  PASSED";
            pass_count <= pass_count + 1;
        else
            report "  FAILED" severity error;
            report "  Expected: 38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b";
            report "  Got:      " & to_hstring(hash_out);
            fail_count <= fail_count + 1;
        end if;

        wait for CLK_PERIOD * 5;

        ------------------------------------------------------------------------
        -- Test 3: "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
        ------------------------------------------------------------------------
        test_count <= test_count + 1;
        report "Test 3: SHA-384(""abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"")";

        wait until rising_edge(clk) and ready = '1';
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        send_block(clk, data_in, data_valid, last_block, ready, tv3_block, true);

        wait until rising_edge(clk) and hash_valid = '1';
        wait for 1 ns;

        hash_match := (hash_out = tv3_expected);
        if hash_match then
            report "  PASSED";
            pass_count <= pass_count + 1;
        else
            report "  FAILED" severity error;
            report "  Expected: 3391fdddfc8dc7393707a65b1b4709397cf8b1d162af05abfe8f450de5f36bc6b0455a8520bc4e6f5fe95b1fe3c8452b";
            report "  Got:      " & to_hstring(hash_out);
            fail_count <= fail_count + 1;
        end if;

        wait for CLK_PERIOD * 5;

        ------------------------------------------------------------------------
        -- Test 4: Two-block message (112 bytes = 896 bits)
        ------------------------------------------------------------------------
        test_count <= test_count + 1;
        report "Test 4: SHA-384(112-byte message) - TWO BLOCKS";

        wait until rising_edge(clk) and ready = '1';
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        -- Send first block (not last)
        send_block(clk, data_in, data_valid, last_block, ready, tv4_block1, false);

        -- Send second block (last)
        send_block(clk, data_in, data_valid, last_block, ready, tv4_block2, true);

        wait until rising_edge(clk) and hash_valid = '1';
        wait for 1 ns;

        hash_match := (hash_out = tv4_expected);
        if hash_match then
            report "  PASSED";
            pass_count <= pass_count + 1;
        else
            report "  FAILED" severity error;
            report "  Expected: 09330c33f71147e83d192fc782cd1b4753111b173b3b05d22fa08086e3b0f712fcc7c71a557e2db966c3e9fa91746039";
            report "  Got:      " & to_hstring(hash_out);
            fail_count <= fail_count + 1;
        end if;

        wait for CLK_PERIOD * 5;

        ------------------------------------------------------------------------
        -- Summary
        ------------------------------------------------------------------------
        report "========================================";
        report "Test Summary:";
        report "  Total:  " & integer'image(test_count);
        report "  Passed: " & integer'image(pass_count);
        report "  Failed: " & integer'image(fail_count);
        report "========================================";

        if fail_count = 0 then
            report "ALL TESTS PASSED!" severity note;
        else
            report "SOME TESTS FAILED!" severity error;
        end if;

        test_done <= true;
        wait;
    end process;

end architecture sim;
