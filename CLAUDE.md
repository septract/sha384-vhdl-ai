# Claude Code Project Context

## Build & Test

```bash
# Compile, elaborate, and run tests
nvc -a sha384_pkg.vhd sha384.vhd sha384_tb.vhd && nvc -e sha384_tb && nvc -r sha384_tb
```

## Project Structure

| File | Purpose |
|------|---------|
| `sha384_pkg.vhd` | Constants (K, H_INIT) and functions (sigma, ch, maj) |
| `sha384.vhd` | Main synthesizable SHA-384 core |
| `sha384_tb.vhd` | Testbench with 4 NIST test vectors |

## SHA-384 Algorithm Quick Reference

- **Block size**: 1024 bits (16 × 64-bit words)
- **Rounds**: 80
- **Output**: 384 bits (first 6 of 8 hash words)

```
T1 = h + Σ1(e) + Ch(e,f,g) + K[t] + W[t]
T2 = Σ0(a) + Maj(a,b,c)
h=g, g=f, f=e, e=d+T1, d=c, c=b, b=a, a=T1+T2
```

## Debugging Crypto HDL

1. **Verify constants first** - K values and initial hash against FIPS 180-4
2. **Test functions in isolation** - sigma, ch, maj with known inputs
3. **Trace round-by-round** - find FIRST divergence from reference
4. **Check W schedule** - especially circular buffer indexing for t≥16

## Key Specifications

- [FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.180-4.pdf) - SHA-384/512 specification
- [RFC 6234](https://datatracker.ietf.org/doc/html/rfc6234) - Reference C implementation
- [Test Vectors](https://di-mgt.com.au/sha_testvectors.html) - NIST test cases
