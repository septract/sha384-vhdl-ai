# Security Audit: Side-Channel Vulnerability Analysis

> **Scope**: SHA-384 VHDL implementations in this repository
> **Date**: December 2024
> **Status**: Educational/Experimental (NOT production-ready)

## Executive Summary

This audit examines the SHA-384 VHDL implementations for side-channel vulnerabilities. The key findings are:

| Side-Channel Type | Risk Level | Notes |
|-------------------|------------|-------|
| **Timing** | LOW | Constant cycle count per block; no early termination |
| **Power (DPA/SPA)** | HIGH | Variable carry propagation and switching activity |
| **Electromagnetic** | HIGH | Same root causes as power |
| **Cache** | N/A | Hardware implementation; no cache |

**Bottom line**: These implementations are constant-time at the cycle level but vulnerable to power analysis attacks. This is acceptable for educational use but would require hardening for security-critical applications.

---

## 1. Timing Side-Channels

### 1.1 Assessment: LOW RISK

All implementations execute a **fixed number of cycles per block** regardless of input data:

| Implementation | Cycles/Block | Data-Dependent Branches |
|----------------|--------------|------------------------|
| `sha384.vhd` | ~117 | None |
| `sha384_fast.vhd` | ~28 | None |
| `sha384_fast8.vhd` | ~18 | None |
| `sha384_pipeline.vhd` | 10 (latency) | None |
| `sha384_multi.vhd` | 10 (latency) | None |

### 1.2 Verified Properties

- **No early termination**: All 80 rounds execute regardless of intermediate values
- **No secret-dependent branches**: All `if`/`case` statements depend on:
  - Round counter (public)
  - Control signals (`start`, `data_valid`, `last_block`)
  - Never on message content or intermediate hash values
- **Fixed loop counts**: All loops have compile-time constant bounds

### 1.3 Minor Observations

**LOAD_BLOCK timing** (`sha384.vhd`, `sha384_fast.vhd`):
- State machine waits for external `data_valid` signal
- Timing depends on interface, not message content
- **Risk**: Negligible (doesn't leak message bits)

**Pipeline valid propagation** (`sha384_pipeline.vhd`):
- Active pipeline stages reveal processing activity
- Could leak message block boundaries for multi-block messages
- **Risk**: Low (reveals message length, not content)

---

## 2. Power Side-Channels

### 2.1 Assessment: HIGH RISK

The implementations have **variable power consumption** correlated with message content through:

1. **Carry propagation in additions** - longer carry chains consume more power
2. **Switching activity** - bit transitions in registers correlate with data values
3. **W schedule dependencies** - cascading computations amplify correlations

### 2.2 Critical Vulnerability: W Schedule Dependency Chain

**Affected files**: `sha384_fast8.vhd:184-245`, `sha384_pipeline.vhd:259-300`

For rounds >= 16, the W schedule values are computed in a **cascading dependency chain** within a single clock cycle:

```
w0, w1 computed in parallel (independent)
   |
   v
w2 = f(w0), w3 = f(w1)    -- depend on w0, w1
   |
   v
w4 = f(w2), w5 = f(w3)    -- depend on w2, w3
   |
   v
w6 = f(w4), w7 = f(w5,w0) -- depend on w4, w5
```

**Location** (`sha384_fast8.vhd:199-245`):
```vhdl
-- w2 depends on w0
w2 := std_logic_vector(
    unsigned(small_sigma1(w0)) +  -- <-- DEPENDENCY ON w0
    unsigned(W(w_idx(t - 5))) +
    unsigned(small_sigma0(W(w_idx(t - 13)))) +
    unsigned(W(w_idx(t - 14)))
);
```

**Attack vector**:
- Power consumption during `small_sigma1(w0)` depends on bit pattern of `w0`
- `w0` contains message schedule data derived from input
- Differential Power Analysis (DPA) can correlate power traces with hypothetical intermediate values

### 2.3 High Vulnerability: Nested K+W Pre-computation

**Affected file**: `sha384_fast.vhd:350-367`

When `t >= 12`, pre-computation involves **double-nested sigma operations**:

```vhdl
kw_pre(2) <= add2(K(...), std_logic_vector(
    unsigned(small_sigma1(std_logic_vector(
        unsigned(small_sigma1(w2)) +     -- Nested sigma1!
        unsigned(W(w_idx(t - 3))) +
        unsigned(small_sigma0(W(w_idx(t - 11)))) +
        unsigned(W(w_idx(t - 12)))))) +
    unsigned(W(w_idx(t - 1))) +
    unsigned(small_sigma0(W(w_idx(t - 9)))) +
    unsigned(W(w_idx(t - 10)))));
```

**Attack vector**:
- Multiple levels of addition create deep carry chains
- Outer `sigma1` depends on result of inner arithmetic
- Total power varies significantly with intermediate values

### 2.4 Medium Vulnerability: All Arithmetic Operations

Every addition operation has variable carry propagation:

```vhdl
-- T1 computation (all implementations)
T1 = h + sigma1(e) + Ch(e,f,g) + K[t] + W[t]
```

- Adding two 64-bit values: carry can propagate 0-64 bits
- Longer carry chains = more switching activity = more power
- CSA reduces but doesn't eliminate this (final `csa_reduce` uses standard addition)

---

## 3. Electromagnetic Side-Channels

### 3.1 Assessment: HIGH RISK

Same root causes as power side-channels:
- Current flow variations create EM emanations
- Unshielded FPGA implementations are particularly vulnerable
- EM probes can capture localized emissions from specific logic regions

---

## 4. Vulnerability Summary Table

| ID | Severity | File | Lines | Description |
|----|----------|------|-------|-------------|
| SCA-01 | CRITICAL | `sha384_fast8.vhd` | 184-245 | W schedule dependency chain |
| SCA-02 | CRITICAL | `sha384_pipeline.vhd` | 259-300 | W schedule dependency chain |
| SCA-03 | HIGH | `sha384_fast.vhd` | 350-367 | Nested K+W pre-computation |
| SCA-04 | MEDIUM | All | Various | Variable carry propagation in additions |
| SCA-05 | LOW | `sha384_pipeline.vhd` | Various | Valid bit reveals block boundaries |
| SCA-06 | LOW | `sha384.vhd`, `sha384_fast.vhd` | Various | LOAD_BLOCK external timing |

---

## 5. Mitigation Recommendations

### For Timing Side-Channels (already mitigated)
- Current implementations are constant-time at cycle level
- No changes needed for timing resistance

### For Power/EM Side-Channels (not implemented)

**Architectural mitigations:**

1. **Separate W pre-computation**: Compute full W[0..79] in dedicated cycles before compression
   - Breaks dependency chain across multiple cycles
   - Reduces correlation between power and single-cycle computations

2. **Pipeline W computation**: Add dedicated pipeline stages for W schedule
   - Each stage computes one or two W values
   - Spreads power variations across time

**Algorithmic mitigations:**

3. **Boolean masking**: Split secret values into random shares
   ```
   w_masked = w XOR mask
   -- Compute on masked values, unmask at end
   ```
   - Decorrelates power from actual values
   - Requires careful implementation to avoid leaks in masking/unmasking

4. **Threshold implementations**: Use secret sharing with threshold schemes
   - Most robust but significant area/performance overhead

**Physical mitigations:**

5. **Noise injection**: Add random dummy operations
6. **Balanced logic**: Use dual-rail encoding (every bit represented by complementary signals)
7. **EM shielding**: Physical countermeasures for deployed hardware

---

## 6. Risk Assessment by Use Case

| Use Case | Timing Risk | Power/EM Risk | Recommendation |
|----------|-------------|---------------|----------------|
| Educational/Learning | N/A | N/A | Current implementation OK |
| FPGA benchmarking | Low | Medium | Acceptable for throughput testing |
| Software hash verification | Low | Low | Attacker can't measure hardware power |
| Embedded secure boot | Low | **HIGH** | Implement masking or use hardened core |
| Cryptocurrency/HSM | Low | **CRITICAL** | Do not use; requires full hardening |

---

## 7. Conclusion

These SHA-384 implementations successfully avoid **timing side-channels** through constant-time design patterns:
- Fixed iteration counts
- No data-dependent branches
- Deterministic state machine transitions

However, they are **vulnerable to power analysis attacks** due to:
- Cascading W schedule computations within single cycles
- Variable carry propagation in arithmetic operations
- No masking or balanced logic countermeasures

**For educational and benchmarking purposes**, these implementations are suitable. **For security-critical applications**, additional hardening would be required, typically involving masked arithmetic and separated W pre-computation stages.

---

## References

- [FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.180-4.pdf) - SHA-384 specification
- [Kocher et al., "Differential Power Analysis"](https://link.springer.com/chapter/10.1007/3-540-48405-1_25) - Original DPA paper
- [Mangard et al., "Power Analysis Attacks"](https://link.springer.com/book/10.1007/978-0-387-38162-6) - Comprehensive reference
- [Tiri & Verbauwhede, "A Logic Level Design Methodology for a Secure DPA Resistant ASIC"](https://ieeexplore.ieee.org/document/1253176) - Balanced logic countermeasures
