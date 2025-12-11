# Claude Code Project Context

> **WARNING: AI-generated code - NOT for production use. Educational/experimental only.**

## Build & Test

```bash
# Baseline implementation
nvc -a sha384_pkg.vhd sha384.vhd sha384_tb.vhd && nvc -e sha384_tb && nvc -r sha384_tb

# 4x unrolled optimized implementation
nvc -a sha384_fast_pkg.vhd sha384_fast.vhd sha384_fast_tb.vhd && nvc -e sha384_fast_tb && nvc -r sha384_fast_tb

# 8x unrolled optimized implementation
nvc -a sha384_fast_pkg.vhd sha384_fast8.vhd sha384_fast8_file_tb.vhd && nvc -e sha384_fast8_file_tb && nvc -r sha384_fast8_file_tb

# Comprehensive test suite (NIST vectors, boundary tests, multi-block, random)
python3 compare_sha384.py --count 10 --max-len 500

# Quick verification (fewer tests, faster)
python3 compare_sha384.py --quick

# Verify constants only (no VHDL simulation)
python3 compare_sha384.py --skip-vhdl
```

## Project Structure

| File | Purpose |
|------|---------|
| `sha384_pkg.vhd` | Constants (K, H_INIT) and functions (sigma, ch, maj) |
| `sha384.vhd` | Baseline SHA-384 core (1 round/cycle, ~117 cycles/block) |
| `sha384_tb.vhd` | Testbench for baseline with 4 NIST test vectors |
| `sha384_fast_pkg.vhd` | CSA functions (carry-save adders) for optimized cores |
| `sha384_fast.vhd` | 4x unrolled core (~28 cycles/block, 4.2x speedup) |
| `sha384_fast_tb.vhd` | Testbench for 4x with cycle counting |
| `sha384_fast8.vhd` | 8x unrolled core (~18 cycles/block, 6.5x speedup) |
| `sha384_file_tb.vhd` | File-based testbench (reads test_vectors.txt) |
| `sha384_fast_file_tb.vhd` | File-based testbench for 4x (512-bit interface) |
| `sha384_fast8_file_tb.vhd` | File-based testbench for 8x (512-bit interface) |
| `compare_sha384.py` | Comprehensive test suite: NIST vectors, boundary tests, OpenSSL cross-check |
| `OPTIMIZATIONS.md` | Detailed documentation of all optimizations |

## SHA-384 Algorithm Quick Reference

- **Block size**: 1024 bits (16 × 64-bit words)
- **Rounds**: 80
- **Output**: 384 bits (first 6 of 8 hash words)

```
T1 = h + Σ1(e) + Ch(e,f,g) + K[t] + W[t]
T2 = Σ0(a) + Maj(a,b,c)
h=g, g=f, f=e, e=d+T1, d=c, c=b, b=a, a=T1+T2
```

## Optimizations Implemented

1. **4x/8x loop unrolling** - Process multiple rounds per cycle
2. **Carry-Save Adders (CSA)** - Reduce critical path for additions
3. **512-bit data interface** - Load 8 words/cycle instead of 1
4. **K+W pre-computation** - Compute K[t]+W[t] one cycle ahead
5. **Circular W buffer** - Modular indexing instead of shifting

## Test Coverage

The `compare_sha384.py` test suite includes:

1. **FIPS 180-4 Constant Verification** - K[0..79] and H_INIT[0..7] checked against spec
2. **NIST CAVP Test Vectors** - Official test vectors (empty, "abc", 56-byte, 112-byte)
3. **Boundary Length Tests** - Critical padding edge cases (55, 111, 127, 128 bytes, etc.)
4. **Multi-Block Stress Tests** - Messages requiring 5, 10, 15 blocks
5. **OpenSSL Cross-Verification** - Independent hash verification
6. **Random Tests** - Randomized input for broad coverage

## Debugging Crypto HDL

1. **Verify constants first** - K values and initial hash against FIPS 180-4
2. **Test functions in isolation** - sigma, ch, maj with known inputs
3. **Trace round-by-round** - find FIRST divergence from reference
4. **Check W schedule** - especially circular buffer indexing for t≥16
5. **Use compare_sha384.py** - comprehensive testing catches edge cases

## Key Specifications

- [FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.180-4.pdf) - SHA-384/512 specification
- [RFC 6234](https://datatracker.ietf.org/doc/html/rfc6234) - Reference C implementation
- [Test Vectors](https://di-mgt.com.au/sha_testvectors.html) - NIST test cases
