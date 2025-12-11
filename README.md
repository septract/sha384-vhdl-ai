# SHA-384 VHDL Implementation

> **WARNING: This code is AI-generated and has NOT been audited for security or correctness. Do NOT use in production systems. This repository is for educational and experimental purposes only. Cryptographic implementations require rigorous review by domain experts before any real-world use.**

A synthesizable VHDL implementation of the SHA-384 cryptographic hash function, conforming to [FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.180-4.pdf).

## Features

- **Fully synthesizable** RTL design suitable for FPGA/ASIC
- **Multi-block message support** - handles messages of arbitrary length
- **Verified** against NIST test vectors and randomized testing
- **Multiple implementations** - baseline and high-throughput optimized versions
- **Clean interface** - simple handshaking protocol for data input

## Implementations

| Implementation | File | Cycles/Block | Throughput | Speedup | Description |
|----------------|------|--------------|------------|---------|-------------|
| Baseline | `sha384.vhd` | ~117 | 1/117 blk/cyc | 1x | Simple 1 round/cycle |
| Fast (4x) | `sha384_fast.vhd` | ~28 | 1/28 blk/cyc | 4.2x | 4 rounds/cycle, CSA |
| Fast (8x) | `sha384_fast8.vhd` | ~18 | 1/18 blk/cyc | 6.5x | 8 rounds/cycle, CSA |
| **Pipeline** | `sha384_pipeline.vhd` | 10 (lat) | **1 blk/cyc** | **~117x** | Full 10-stage pipeline |
| **Multi (4x)** | `sha384_multi.vhd` | 10 (lat) | **4 blk/cyc** | **~468x** | 4 parallel pipelines |

See [OPTIMIZATIONS.md](OPTIMIZATIONS.md) for detailed optimization documentation.

## Files

| File | Description |
|------|-------------|
| `sha384_pkg.vhd` | Package with constants (K, H_INIT) and functions |
| `sha384.vhd` | Baseline SHA-384 core (1 round/cycle) |
| `sha384_tb.vhd` | Testbench for baseline with NIST test vectors |
| `sha384_fast_pkg.vhd` | Package with CSA functions for optimized cores |
| `sha384_fast.vhd` | 4x unrolled optimized core |
| `sha384_fast_tb.vhd` | Testbench for 4x with cycle counting |
| `sha384_fast8.vhd` | 8x unrolled optimized core |
| `sha384_pipeline.vhd` | Full 10-stage pipelined core (1 block/cycle) |
| `sha384_multi.vhd` | Multi-core wrapper (N parallel pipelines) |
| `sha384_file_tb.vhd` | File-based testbench for baseline |
| `sha384_fast_file_tb.vhd` | File-based testbench for 4x |
| `sha384_fast8_file_tb.vhd` | File-based testbench for 8x |
| `sha384_pipeline_file_tb.vhd` | File-based testbench for pipeline |
| `sha384_multi_file_tb.vhd` | File-based testbench for multi (4 cores) |
| `compare_sha384.py` | Comprehensive test suite with NIST vectors |
| `OPTIMIZATIONS.md` | Detailed optimization documentation |

## Interface

### Baseline (64-bit input)

```vhdl
entity sha384 is
    port (
        clk        : in  std_logic;                      -- Clock
        reset      : in  std_logic;                      -- Synchronous reset (active high)
        start      : in  std_logic;                      -- Start new hash
        data_in    : in  std_logic_vector(63 downto 0);  -- Input data word
        data_valid : in  std_logic;                      -- Input data valid
        last_block : in  std_logic;                      -- This is the final block
        ready      : out std_logic;                      -- Ready to accept data
        hash_out   : out std_logic_vector(383 downto 0); -- 384-bit hash output
        hash_valid : out std_logic                       -- Hash output valid
    );
end entity;
```

### Optimized (512-bit input)

```vhdl
entity sha384_fast is  -- or sha384_fast8
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        start      : in  std_logic;
        data_in    : in  std_logic_vector(511 downto 0); -- 8 words per cycle
        data_valid : in  std_logic;
        last_block : in  std_logic;
        ready      : out std_logic;
        hash_out   : out std_logic_vector(383 downto 0);
        hash_valid : out std_logic
    );
end entity;
```

### Pipelined (1024-bit input, 1 block/cycle throughput)

```vhdl
entity sha384_pipeline is
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        start      : in  std_logic;                        -- Start new message
        data_in    : in  std_logic_vector(1023 downto 0);  -- Full block at once
        data_valid : in  std_logic;
        last_block : in  std_logic;
        ready      : out std_logic;
        h_in       : in  std_logic_vector(511 downto 0);   -- For multi-block continuation
        use_h_in   : in  std_logic;
        hash_out   : out std_logic_vector(383 downto 0);
        hash_valid : out std_logic;
        h_out      : out std_logic_vector(511 downto 0);   -- Intermediate hash state
        h_out_valid: out std_logic
    );
end entity;
```

## Build & Test

Requires [NVC](https://github.com/nickg/nvc) VHDL simulator (or any VHDL-2008 compatible simulator).

### Baseline

```bash
nvc -a sha384_pkg.vhd sha384.vhd sha384_tb.vhd && nvc -e sha384_tb && nvc -r sha384_tb
```

### Optimized (4x)

```bash
nvc -a sha384_fast_pkg.vhd sha384_fast.vhd sha384_fast_tb.vhd && nvc -e sha384_fast_tb && nvc -r sha384_fast_tb
```

### Optimized (8x)

```bash
nvc -a sha384_fast_pkg.vhd sha384_fast8.vhd sha384_fast8_file_tb.vhd && nvc -e sha384_fast8_file_tb && nvc -r sha384_fast8_file_tb
```

### Pipelined (maximum throughput)

```bash
nvc -a sha384_fast_pkg.vhd sha384_pipeline.vhd sha384_pipeline_file_tb.vhd && nvc -e sha384_pipeline_file_tb && nvc -r sha384_pipeline_file_tb
```

### Multi-core (4 parallel pipelines)

```bash
nvc -a sha384_fast_pkg.vhd sha384_pipeline.vhd sha384_multi.vhd sha384_multi_file_tb.vhd && nvc -e sha384_multi_file_tb && nvc -r sha384_multi_file_tb
```

### Comprehensive Test Suite

```bash
# Full test suite (NIST vectors, boundary tests, multi-block, random)
python3 compare_sha384.py --count 10 --max-len 500

# Quick verification
python3 compare_sha384.py --quick

# Verify constants only (no VHDL simulation)
python3 compare_sha384.py --skip-vhdl
```

The test suite includes:
- **FIPS 180-4 constant verification** - K[0..79] and H_INIT[0..7] checked against spec
- **NIST CAVP test vectors** - Official test vectors (empty, "abc", 56-byte, 112-byte)
- **Boundary length tests** - Critical padding edge cases (55, 111, 127, 128 bytes)
- **Multi-block stress tests** - Messages requiring 5, 10, 15 blocks
- **OpenSSL cross-verification** - Independent hash verification (if available)
- **Random tests** - Randomized input for broad coverage

## Usage Example

To hash a message:

1. Assert `start` for one clock cycle
2. For each 1024-bit block:
   - **Baseline**: Send 16 × 64-bit words with `data_valid` high
   - **Optimized**: Send 2 × 512-bit words with `data_valid` high
   - Set `last_block` high with the final word of the last block
3. Wait for `hash_valid` to go high
4. Read the 384-bit hash from `hash_out`

Note: The caller is responsible for padding the message according to SHA-384 rules (append 0x80, pad to 896 mod 1024 bits, append 128-bit length).

## Algorithm Summary

SHA-384 is part of the SHA-2 family:

- **Block size**: 1024 bits (16 × 64-bit words)
- **Word size**: 64 bits
- **Rounds**: 80
- **Output**: 384 bits (first 6 of 8 hash words)

Core operations per round:
```
T1 = h + Σ1(e) + Ch(e,f,g) + K[t] + W[t]
T2 = Σ0(a) + Maj(a,b,c)
(a,b,c,d,e,f,g,h) = (T1+T2, a, b, c, d+T1, e, f, g)
```

## Test Vectors

Test vectors sourced from:
- [di-mgt.com.au SHA Test Vectors](https://di-mgt.com.au/sha_testvectors.html)
- [NIST CAVP](https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program)
- Python `hashlib` (for randomized testing)

## References

- [FIPS 180-4: Secure Hash Standard](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.180-4.pdf)
- [RFC 6234: US Secure Hash Algorithms](https://datatracker.ietf.org/doc/html/rfc6234)
- [NIST CAVP - Secure Hashing](https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/secure-hashing)

## License

BSD 3-Clause License. See [LICENSE](LICENSE) file.
