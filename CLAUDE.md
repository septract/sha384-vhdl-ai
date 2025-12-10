# SHA-384 VHDL Implementation

## Project Overview

This project implements SHA-384 (and by extension SHA-512) in synthesizable VHDL. SHA-384 is part of the SHA-2 family defined in FIPS 180-4.

## Build & Test

Uses NVC (VHDL simulator) on macOS:

```bash
# Analyze (compile) files - order matters for dependencies
nvc -a sha384_pkg.vhd sha384.vhd sha384_tb.vhd

# Elaborate testbench
nvc -e sha384_tb

# Run simulation
nvc -r sha384_tb
```

## Debugging Strategy for Cryptographic Implementations

When implementing crypto algorithms in HDL, bugs are notoriously hard to find because:
- Small errors propagate through many rounds
- Most intermediate values look "random"
- Off-by-one errors in indexing are common

### Recommended Debugging Approach

1. **Verify components in isolation first**
   - Test each function (sigma, ch, maj) with known inputs
   - Verify constants (K values, initial hash) against spec
   - Test basic operations (rotate, shift, add) independently

2. **Find authoritative intermediate values**
   - NIST provides example PDFs with step-by-step values
   - Use multiple sources to cross-check
   - Don't trust random online calculators without verification

3. **Trace round-by-round**
   - Compare working variables (a-h) after each round
   - Find the FIRST round where values diverge from reference
   - The bug is in that round's computation or the previous round's output

4. **For message schedule (W) bugs**
   - W[0-15] come directly from input - verify padding is correct
   - W[16-79] use sigma functions - verify formulas match spec
   - Check array indexing carefully (especially in circular buffers)

5. **Common bugs to check**
   - Wrong rotation amounts (SHA-256 vs SHA-512 use different values)
   - Byte order / endianness issues
   - Off-by-one in round counting (should be 0-79 = 80 rounds)
   - Signal vs variable timing in clocked implementations

## Key Files

| File | Purpose |
|------|---------|
| `sha384_pkg.vhd` | Constants (K, H_INIT) and functions (sigma, ch, maj) |
| `sha384.vhd` | Main synthesizable core with state machine |
| `sha384_tb.vhd` | Testbench with NIST test vectors |
| `sha384_ref_tb.vhd` | Pure combinational reference (no clocking) |
| `test_vectors.txt` | Documented test cases from NIST |

## SHA-384/512 Algorithm Summary

- **Block size**: 1024 bits (16 × 64-bit words)
- **Word size**: 64 bits
- **Rounds**: 80
- **Output**: 384 bits (SHA-384) or 512 bits (SHA-512)

Key formulas:
```
T1 = h + Σ1(e) + Ch(e,f,g) + K[t] + W[t]
T2 = Σ0(a) + Maj(a,b,c)

Working variable update:
h=g, g=f, f=e, e=d+T1, d=c, c=b, b=a, a=T1+T2
```

## References

- FIPS 180-4: https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.180-4.pdf
- NIST Examples: https://csrc.nist.gov/projects/cryptographic-standards-and-guidelines/example-values
- RFC 6234: https://datatracker.ietf.org/doc/html/rfc6234
