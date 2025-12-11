# SHA-384 Optimization Guide

This document describes the optimizations implemented in `sha384_fast` compared to the baseline `sha384` implementation.

## Performance Summary

| Implementation | Cycles/Block | Speedup |
|----------------|--------------|---------|
| `sha384` (baseline) | ~117 | 1x |
| `sha384_fast` (4x) | 28 | 4.2x |
| `sha384_fast8` (8x) | ~18 | **6.5x** |

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

### 6. 8x Loop Unrolling (sha384_fast8)

**File:** `sha384_fast8.vhd`

Process 8 SHA-384 rounds per clock cycle instead of 4.

```
4x version: 20 cycles for compression (4 rounds/cycle)
8x version: 10 cycles for compression (8 rounds/cycle)
```

#### State Cascade

The 8-round cascade tracks working variables through all 8 rounds:

```
Round t:   (a,b,c,d,e,f,g,h) → (a0,a,b,c,e0,e,f,g)
Round t+1: (a0,a,b,c,e0,e,f,g) → (a1,a0,a,b,e1,e0,e,f)
...
Round t+7: (a6,a5,a4,a3,e6,e5,e4,e3) → (a7,a6,a5,a4,e7,e6,e5,e4)
```

Final registered state: `(va,vb,vc,vd,ve,vf,vg,vh) = (a7,a6,a5,a4,e7,e6,e5,e4)`

#### W Schedule Dependencies

For t >= 16, need to compute 8 W values with a dependency chain:

```
w0 = σ1(W[t-2]) + W[t-7] + σ0(W[t-15]) + W[t-16]  -- from buffer
w1 = σ1(W[t-1]) + W[t-6] + σ0(W[t-14]) + W[t-15]  -- from buffer
w2 = σ1(w0) + W[t-5] + σ0(W[t-13]) + W[t-14]      -- depends on w0
w3 = σ1(w1) + W[t-4] + σ0(W[t-12]) + W[t-13]      -- depends on w1
w4 = σ1(w2) + W[t-3] + σ0(W[t-11]) + W[t-12]      -- depends on w2
w5 = σ1(w3) + W[t-2] + σ0(W[t-10]) + W[t-11]      -- depends on w3
w6 = σ1(w4) + W[t-1] + σ0(W[t-9]) + W[t-10]       -- depends on w4
w7 = σ1(w5) + w0 + σ0(W[t-8]) + W[t-9]            -- depends on w5, w0
```

#### Performance

| Implementation | Cycles/Block | Speedup vs Baseline |
|----------------|--------------|---------------------|
| `sha384` (baseline) | ~117 | 1x |
| `sha384_fast` (4x) | 28 | 4.2x |
| `sha384_fast8` (8x) | ~18 | **6.5x** |

#### Trade-offs

- **Longer critical path**: 8 cascaded rounds + W dependency chain
- **More combinational logic**: 8 T1/T2 computations, 8 W computations
- **Higher resource usage**: More adders, more routing
- **May limit Fmax**: Very deep combinational path may reduce achievable clock frequency

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

---

## Pipeline Optimizations (sha384_pipeline, sha384_multi)

The following optimizations are implemented in `sha384_pipeline.vhd` and `sha384_multi.vhd` for maximum throughput:

### 7. Full Pipelining

**Impact: 🔥🔥🔥 Highest**

Process multiple blocks simultaneously through a 10-stage pipeline. Each stage handles 8 rounds, allowing a new block to enter every cycle (after pipeline fills).

```
┌──────────┐   ┌──────────┐   ┌──────────┐       ┌──────────┐
│ Stage 0  │ → │ Stage 1  │ → │ Stage 2  │ → ... │ Stage 9  │ → Hash
│ Rnd 0-7  │   │ Rnd 8-15 │   │ Rnd 16-23│       │ Rnd 72-79│
└──────────┘   └──────────┘   └──────────┘       └──────────┘
   Block N      Block N-1      Block N-2          Block N-9
```

**Performance:**
- Latency: 10 cycles per block (same as sha384_fast8)
- Throughput: 1 block per cycle (after pipeline fills)
- **10x throughput improvement** for streaming data

**Architecture:**
```vhdl
-- Each pipeline stage holds:
type pipeline_stage is record
    valid     : std_logic;           -- Stage contains valid data
    last      : std_logic;           -- This is the final block
    msg_id    : unsigned(7 downto 0); -- Message identifier
    hv        : word64_array(0 to 7); -- Hash state for this message
    va..vh    : word64;              -- Working variables
    W         : word64_array(0 to 15); -- Message schedule
end record;
```

**Multi-block handling:**
- Each block carries its hash state (H values) through the pipeline
- For multi-block messages, intermediate hash updates are forwarded
- `msg_id` tracks which message each block belongs to

### 8. 1024-bit Data Interface

**Impact: 🔥 Quick win**

Load entire 1024-bit block in a single cycle instead of two 512-bit loads.

```vhdl
-- Previous (sha384_fast8)
data_in : in std_logic_vector(511 downto 0);  -- 2 cycles to load

-- New (sha384_pipeline)
data_in : in std_logic_vector(1023 downto 0); -- 1 cycle to load
```

**Savings:** 1 cycle per block during load phase.

### 9. Merged State Machine

**Impact: 🔥 Moderate**

Eliminate state machine overhead by removing intermediate states:

```
-- Previous flow (sha384_fast8):
IDLE → LOAD_BLOCK (2 cycles) → COMPRESS (10 cycles) → UPDATE_HASH → DONE
Total overhead: ~4-5 cycles

-- New flow (sha384_pipeline):
Direct injection into pipeline stage 0
No intermediate states for streaming mode
Total overhead: 0 cycles (pipelined)
```

**Implementation:**
- Block loads directly into pipeline stage 0
- Hash update merged into final pipeline stage
- No IDLE/DONE states needed for continuous streaming

### 10. Speculative W Pre-computation

**Impact: 🔥 Moderate**

Compute W schedule values for the next stage in parallel with current round computation:

```vhdl
-- In stage N, while processing rounds 8N to 8N+7:
-- Simultaneously compute W values for stage N+1
W_next(0..7) <= compute_w_schedule(W_current, round_base + 8);
```

**Benefits:**
- Removes W computation from critical path
- Each stage only performs round computation
- W values ready when block advances to next stage

### 11. Parallel Hash Engines (sha384_multi)

**Impact: 🔥🔥🔥 Linear scaling**

Instantiate N parallel sha384_pipeline cores for independent messages:

```vhdl
entity sha384_multi is
    generic (
        NUM_CORES : positive := 4
    );
    port (
        data_in    : in  std_logic_vector(NUM_CORES*1024-1 downto 0);
        hash_out   : out std_logic_vector(NUM_CORES*384-1 downto 0);
        ...
    );
end entity;
```

**Performance:**
- 4 cores: 4 blocks/cycle throughput
- 8 cores: 8 blocks/cycle throughput
- Linear scaling with FPGA resources

**Best for:** Hashing many independent messages (e.g., cryptocurrency mining, certificate batch validation, Merkle tree construction).

---

## Performance Summary (All Implementations)

| Implementation | Cycles/Block | Throughput | Speedup |
|----------------|--------------|------------|---------|
| `sha384` (baseline) | ~117 | 1/117 blocks/cyc | 1x |
| `sha384_fast` (4x) | 28 | 1/28 blocks/cyc | 4.2x |
| `sha384_fast8` (8x) | ~18 | 1/18 blocks/cyc | 6.5x |
| `sha384_pipeline` | 10 (latency) | **1 block/cyc** | **~117x** |
| `sha384_multi` (4 cores) | 10 (latency) | **4 blocks/cyc** | **~468x** |

---

## References

- [FIPS 180-4: Secure Hash Standard](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.180-4.pdf)
- [Improving SHA-2 Hardware Implementations](https://www.researchgate.net/publication/221291748_Improving_SHA-2_Hardware_Implementations)
- [Optimising SHA-512 on FPGAs](https://digital-library.theiet.org/doi/full/10.1049/iet-cdt.2013.0010)
- [1 Gbit/s Partially Unrolled SHA-512](https://www.researchgate.net/publication/225137595_A_1_Gbits_Partially_Unrolled_Architecture_of_Hash_Functions_SHA-1_and_SHA-512)
- [High-Speed SHA-2 Accelerator](https://ieeexplore.ieee.org/document/7011374)
