# SHA-384 VHDL Implementation

A synthesizable VHDL implementation of the SHA-384 cryptographic hash function, conforming to [FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.180-4.pdf).

## Features

- **Fully synthesizable** RTL design suitable for FPGA/ASIC
- **Multi-block message support** - handles messages of arbitrary length
- **Verified** against NIST test vectors from multiple sources
- **Clean interface** - simple handshaking protocol for data input

## Architecture

The implementation uses a state machine with the following states:
- `IDLE` - Waiting for start signal
- `LOAD_BLOCK` - Receiving 16 × 64-bit words (1024-bit block)
- `COMPRESS` - Performing 80 rounds of compression
- `UPDATE_HASH` - Adding working variables to hash state
- `DONE` - Hash complete, output valid

Memory optimization: Uses a 16-word circular buffer for the message schedule (W), computing W[16-79] on-the-fly rather than storing all 80 values.

## Files

| File | Description |
|------|-------------|
| `sha384_pkg.vhd` | Package with constants (K, H_INIT) and functions (σ, Σ, Ch, Maj) |
| `sha384.vhd` | Main SHA-384 core entity |
| `sha384_tb.vhd` | Testbench with 4 NIST test vectors |

## Interface

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

## Build & Test

Requires [NVC](https://github.com/nickg/nvc) VHDL simulator (or any VHDL-2008 compatible simulator):

```bash
# Compile
nvc -a sha384_pkg.vhd sha384.vhd sha384_tb.vhd

# Elaborate
nvc -e sha384_tb

# Run
nvc -r sha384_tb
```

Expected output:
```
SHA-384 Test Suite Starting
Test 1: SHA-384("abc")
  PASSED
Test 2: SHA-384("")
  PASSED
Test 3: SHA-384("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
  PASSED
Test 4: SHA-384(112-byte message) - TWO BLOCKS
  PASSED
Test Summary:
  Total:  4
  Passed: 4
  Failed: 0
ALL TESTS PASSED!
```

## Usage Example

To hash a message:

1. Assert `start` for one clock cycle
2. For each 1024-bit block:
   - Send 16 × 64-bit words with `data_valid` high
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

## References

- [FIPS 180-4: Secure Hash Standard](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.180-4.pdf)
- [RFC 6234: US Secure Hash Algorithms](https://datatracker.ietf.org/doc/html/rfc6234)
- [NIST CAVP - Secure Hashing](https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/secure-hashing)

## License

BSD 3-Clause License. See [LICENSE](LICENSE) file.
