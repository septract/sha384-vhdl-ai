-------------------------------------------------------------------------------
-- SHA-384 Multi-Core Engine
-- Instantiates N parallel sha384_pipeline cores for maximum throughput
--
-- Performance:
--   Throughput: NUM_CORES blocks per cycle (after pipeline fills)
--   Best for: Hashing many independent messages in parallel
--
-- Example: NUM_CORES=4 gives 4 blocks/cycle = ~468x baseline speedup
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sha384_fast_pkg.all;

entity sha384_multi is
    generic (
        NUM_CORES : positive := 4  -- Number of parallel hash engines
    );
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        -- Input interface (NUM_CORES parallel channels)
        start      : in  std_logic_vector(NUM_CORES-1 downto 0);
        data_in    : in  std_logic_vector(NUM_CORES*1024-1 downto 0);
        data_valid : in  std_logic_vector(NUM_CORES-1 downto 0);
        last_block : in  std_logic_vector(NUM_CORES-1 downto 0);
        ready      : out std_logic_vector(NUM_CORES-1 downto 0);
        -- Hash state input (for multi-block continuation)
        h_in       : in  std_logic_vector(NUM_CORES*512-1 downto 0);
        use_h_in   : in  std_logic_vector(NUM_CORES-1 downto 0);
        -- Output interface (NUM_CORES parallel channels)
        hash_out   : out std_logic_vector(NUM_CORES*384-1 downto 0);
        hash_valid : out std_logic_vector(NUM_CORES-1 downto 0);
        h_out      : out std_logic_vector(NUM_CORES*512-1 downto 0);
        h_out_valid: out std_logic_vector(NUM_CORES-1 downto 0)
    );
end entity sha384_multi;

architecture rtl of sha384_multi is
begin

    -- Generate NUM_CORES parallel pipeline instances
    gen_cores: for i in 0 to NUM_CORES-1 generate
        core_inst: entity work.sha384_pipeline
            port map (
                clk         => clk,
                reset       => reset,
                start       => start(i),
                data_in     => data_in((i+1)*1024-1 downto i*1024),
                data_valid  => data_valid(i),
                last_block  => last_block(i),
                ready       => ready(i),
                h_in        => h_in((i+1)*512-1 downto i*512),
                use_h_in    => use_h_in(i),
                hash_out    => hash_out((i+1)*384-1 downto i*384),
                hash_valid  => hash_valid(i),
                h_out       => h_out((i+1)*512-1 downto i*512),
                h_out_valid => h_out_valid(i)
            );
    end generate gen_cores;

end architecture rtl;
