# SHA-384 Optimization Guide

This document describes the optimizations implemented in `sha384_fast` compared to the baseline `sha384` implementation.

## Performance Summary

| Implementation | Cycles/Block | Speedup |
|----------------|--------------|---------|
| `sha384` (baseline) | ~117 | 1x |
| `sha384_fast` | 28 | **4.2x** |

## Implemented Optimizations

### 1. 4x Loop Unrolling

**File:** `sha384_fast.vhd`

Process 4 SHA-384 rounds per clock cycle instead of 1.

```
Baseline: 80 cycles for compression (1 round/cycle)
Optimized: 20 cycles for compression (4 rounds/cycle)
```

The round computation cascades through 4 stages in combinational logic:

```
Round t:   (a,b,c,d,e,f,g,h) → (a0,a,b,c,e0,e,f,g)
Round t+1: (a0,a,b,c,e0,e,f,g) → (a1,a0,a,b,e1,e0,e,f)
Round t+2: (a1,a0,a,b,e1,e0,e,f) → (a2,a1,a0,a,e2,e1,e0,e)
Round t+3: (a2,a1,a0,a,e2,e1,e0,e) → (a3,a2,a1,a0,e3,e2,e1,e0)
```

### 2. Carry-Save Adders (CSA)

**File:** `sha384_fast_pkg.vhd`

Replace chained binary adders with CSA trees to reduce critical path.

**T1 computation** (5 operands → 4 with pre-computation):
```vhdl
-- Original: 4 chained 64-bit additions
T1 = h + Σ1(e) + Ch(e,f,g) + K[t] + W[t]

-- Optimized: CSA tree (2 levels) + final CPA
T1 = add4_csa(h, Σ1(e), Ch(e,f,g), kw_pre)  -- kw_pre = K[t] + W[t]
```

**T2 computation** (2 operands):
```vhdl
T2 = add2(Σ0(a), Maj(a,b,c))
```

CSA functions provided:
- `csa_3_2(a,b,c)` - 3:2 compressor (full adder without carry chain)
- `add4_csa(a,b,c,d)` - 4-operand addition via CSA tree
- `add5_csa(a,b,c,d,e)` - 5-operand addition via CSA tree
- `add2(a,b)` - Simple 2-operand addition

### 3. 512-bit Data Interface

**File:** `sha384_fast.vhd`

Load 8 words (512 bits) per cycle instead of 1 word (64 bits).

```
Baseline: 16 cycles to load 1024-bit block
Optimized: 2 cycles to load 1024-bit block
```

Interface change:
```vhdl
-- Baseline
data_in : in std_logic_vector(63 downto 0)

-- Optimized
data_in : in std_logic_vector(511 downto 0)
```

### 4. K+W Pre-computation

**File:** `sha384_fast.vhd`

Pre-compute `K[t] + W[t]` one cycle ahead, stored in `kw_pre` registers.

Benefits:
- Reduces T1 from 5 operands to 4 operands
- Moves addition out of critical path
- Enables use of `add4_csa` instead of `add5_csa`

```vhdl
-- At end of cycle N (processing rounds t to t+3):
kw_pre(0) <= K[t+4] + W[t+4]
kw_pre(1) <= K[t+5] + W[t+5]
kw_pre(2) <= K[t+6] + W[t+6]
kw_pre(3) <= K[t+7] + W[t+7]

-- At start of cycle N+1:
kw0 := kw_pre(0)  -- Ready to use immediately
```

### 5. Circular W Buffer

**File:** `sha384_fast.vhd`

Use modular indexing instead of shifting the entire W array.

```vhdl
function w_idx(t : unsigned) return integer is
begin
    return to_integer(t(3 downto 0));  -- t mod 16
end function;

-- Access W[t-n] via: W(w_idx(t - n))
```

Benefits:
- Eliminates 1024-bit shift operation every cycle
- Simpler addressing logic

## Cycle Breakdown

| Phase | Baseline | Optimized |
|-------|----------|-----------|
| Load block | 16 | 2 |
| Compression | 80 | 20 |
| Update hash | 1 | 1 |
| **Total** | **97** | **23** |

Note: Actual measured cycles are slightly higher (~28) due to state machine transitions.

## Future Optimization: 8x Loop Unrolling

**Status:** Not implemented (attempted, has bugs)

### Concept

Process 8 rounds per clock cycle:
```
Compression: 10 cycles (8 rounds/cycle) instead of 20 cycles
```

### Challenges

1. **Long combinational chain**: 8 cascaded rounds with data dependencies
2. **W schedule complexity**: Need 8 new W values per cycle, with inter-dependencies:
   ```
   W[t+2] depends on W[t]
   W[t+3] depends on W[t+1]
   W[t+4] depends on W[t+2]
   ...
   ```
3. **Pre-computation complexity**: Computing 8 future K+W values requires knowing W values that depend on values being computed in the same cycle

### Implementation Notes

The 8x unrolling was attempted with:
- 8 T1/T2 computation stages
- 8 W schedule computations with cascading dependencies
- 8-element `kw_pre` array

The implementation compiled but produced incorrect hashes. Likely issues:
- State tracking errors in the 8-round cascade
- W schedule index calculations for the circular buffer
- Pre-computation formula errors for rounds t+8 to t+15

### Estimated Benefit

If implemented correctly:
```
Cycles/block: ~16 (2 load + 10 compress + overhead)
Speedup: ~7x vs baseline, ~1.75x vs current 4x version
```

## Critical Path Analysis

### Baseline (`sha384`)
```
T1 computation: h + Σ1(e) + Ch(e,f,g) + K[t] + W[t]
               = 4 chained 64-bit additions
               ≈ 4 × 64-bit CPA delay
```

### Optimized (`sha384_fast`)
```
T1 computation: add4_csa(h, Σ1(e), Ch(e,f,g), kw_pre)
               = 2 CSA levels + 1 CPA
               ≈ 2 × XOR delay + 1 × 64-bit CPA delay
```

The CSA optimization reduces the critical path by approximately 40-50%, enabling higher clock frequencies.

## References

- [FIPS 180-4: Secure Hash Standard](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.180-4.pdf)
- [Improving SHA-2 Hardware Implementations](https://www.researchgate.net/publication/221291748_Improving_SHA-2_Hardware_Implementations)
- [Optimising SHA-512 on FPGAs](https://digital-library.theiet.org/doi/full/10.1049/iet-cdt.2013.0010)
- [1 Gbit/s Partially Unrolled SHA-512](https://www.researchgate.net/publication/225137595_A_1_Gbits_Partially_Unrolled_Architecture_of_Hash_Functions_SHA-1_and_SHA-512)
