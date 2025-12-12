# SHA-384 Formal Verification with SAW

This directory contains infrastructure for formally verifying the SHA-384 VHDL
implementations against the official Cryptol specification using SAW (Software
Analysis Workbench) from Galois.

## Overview

The verification workflow:

```
VHDL Source → GHDL → Yosys → JSON Netlist → SAW ← Cryptol Spec
```

SAW proves that the synthesized VHDL circuit is functionally equivalent to the
mathematical Cryptol specification of SHA-384.

## Current Status

**✓ Round function verified** - The SHA-384 round function (`sha384_round.vhd`) has been
formally verified against the Cryptol specification using SAW. This proves the core
compression logic is correct for ALL possible inputs.

**Sequential circuits not yet supported** - SAW's experimental Yosys support cannot
handle designs with registers/flip-flops. The full SHA-384 implementation uses a
state machine, so we extracted the combinational round function for verification.

**Verified implementation available** - `sha384_verified.vhd` uses the SAW-verified
round function as a component, providing higher assurance than the baseline.

## Prerequisites

All tools can be installed locally within this project directory (no sudo required).

### Quick Setup (Local Installation)

From the project root directory:

```bash
# Run the setup script (downloads and extracts tools to formal/tools/)
cd formal && ./scripts/setup-tools.sh
```

This downloads ~600MB and creates `formal/tools/` with everything needed.

### Manual Setup

#### 1. OSS CAD Suite (GHDL + Yosys + Plugin)

```bash
cd formal

# Download (~400MB)
curl -LO https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2025-12-12/oss-cad-suite-darwin-arm64-20251212.tgz

# Extract to tools directory
mkdir -p tools
tar -xzf oss-cad-suite-darwin-arm64-20251212.tgz -C tools
rm oss-cad-suite-darwin-arm64-20251212.tgz

# Activate (needed each session, or source in scripts)
source tools/oss-cad-suite/environment
```

#### 2. SAW (Software Analysis Workbench)

```bash
cd formal

# Download with bundled solvers (~245MB) - includes Z3
curl -LO https://github.com/GaloisInc/saw-script/releases/download/v1.4/saw-1.4-macos-14-ARM64-with-solvers.tar.gz

# Extract to tools directory
tar -xzf saw-1.4-macos-14-ARM64-with-solvers.tar.gz -C tools
mv tools/saw-1.4-macos-14-ARM64 tools/saw
rm saw-1.4-macos-14-ARM64-with-solvers.tar.gz
```

### Verify Installation

```bash
cd formal
source tools/oss-cad-suite/environment
export PATH="$PWD/tools/saw/bin:$PATH"

ghdl --version
yosys -m ghdl -p "ghdl --version"
saw --version
```

### Alternative: Docker

If you prefer not to download tools at all:

```bash
docker pull ghcr.io/galoisinc/saw:1.4
# Note: You'd still need GHDL+Yosys for the synthesis step
```

## Known Limitations

**SAW Yosys support is experimental** and currently has issues with sequential circuits
(designs with flip-flops/registers). The SHA-384 implementation uses state machines and
registers, which causes SAW to fail with:

```
Error: Could not find the output bitvector... undetected cycle in the netgraph
```

**Workarounds:**
1. Extract combinational logic (e.g., just the round function) for verification
2. Use SymbiYosys for bounded model checking with PSL assertions instead
3. Report issues to: https://github.com/GaloisInc/saw-script/issues

## Directory Structure

```
formal/
├── README.md              # This file
├── PLAN.md                # Verification plan and strategy
├── sha384_round.vhd       # Round function source (verified by SAW)
├── sha384_round.json      # Generated netlist (gitignored)
├── verify_round.saw       # SAW verification script
├── cryptol/
│   ├── SHA2_Specification.cry   # SHA-2 spec from Galois (reference)
│   └── SHA384.cry               # SHA-384 instantiation (reference)
├── scripts/
│   ├── setup-tools.sh     # Download SAW + OSS CAD Suite locally
│   └── synthesize.sh      # VHDL → JSON pipeline
├── work/                  # GHDL work directory (gitignored)
└── tools/                 # Downloaded tools (~600MB, gitignored)
```

In the main project directory:
- `sha384_round.vhd` - Copy of verified round function (used by sha384_verified.vhd)
- `sha384_verified.vhd` - Full SHA-384 using the verified round component

## Quick Start

### Step 1: Synthesize VHDL to JSON

```bash
cd formal/scripts
./synthesize.sh
```

This will:
1. Analyze `sha384_round.vhd` with GHDL
2. Synthesize to a Yosys JSON netlist
3. Output to `formal/sha384_round.json`

### Step 2: Run SAW Verification

```bash
cd formal
saw verify_round.saw
```

Or use the Makefile from the project root:
```bash
make formal-verify
```

## Verification Strategy

The verification proceeds in phases of increasing complexity:

| Phase | Property | Complexity | Status |
|-------|----------|------------|--------|
| 1 | Constants (K, H_INIT) | Low | ✓ Python test |
| 2 | Logical functions (Ch, Maj, σ) | Low | ✓ In round |
| 3 | Single round | Medium | **✓ SAW verified** |
| 4 | Message schedule | Medium | Pending |
| 5 | Single block hash | High | Blocked (sequential) |
| 6 | Multi-block hash | Very High | Blocked (sequential) |

Phases 5-6 are blocked by SAW's limitation with sequential circuits.
Alternative: use SymbiYosys with PSL assertions for bounded model checking.

## Cryptol Specification

The Cryptol specs in `cryptol/` are from:
https://github.com/GaloisInc/cryptol-specs

They provide a mathematical reference implementation of SHA-384 that closely
follows FIPS 180-4.

## Troubleshooting

### "ghdl plugin not found"

Ensure Yosys can load the GHDL plugin:
```bash
yosys -m ghdl -p "help"
```

If this fails, you need to install the ghdl-yosys-plugin or use OSS CAD Suite.

### "enable_experimental required"

The Yosys integration in SAW is experimental. The `verify_round.saw` script
already includes `enable_experimental;` at the top.

### Verification timeout

SHA-384 has 80 rounds, which creates a large symbolic expression. Try:
- Bounded verification (verify for specific input sizes)
- Compositional verification (verify subcomponents separately)
- Increase SAW timeout: `saw --timeout=3600 scripts/verify.saw`

### JSON netlist issues

If SAW can't parse the JSON:
1. Check Yosys version compatibility
2. Try simplifying the netlist: add `flatten;` pass in Yosys
3. Check for unsupported cell types (e.g., `$pmux`)

## References

- [SAW Documentation](https://saw.galois.com/)
- [SAW Yosys Integration](https://galoisinc.github.io/saw-script/manual/analyzing-hardware-circuits-using-yosys.html)
- [Cryptol](https://cryptol.net/)
- [GHDL-Yosys Plugin](https://github.com/ghdl/ghdl-yosys-plugin)
- [FIPS 180-4 (SHA Standard)](https://doi.org/10.6028/NIST.FIPS.180-4)
