# Plan: SAW Formal Verification for SHA-384 VHDL

## Goal

Set up formal verification using SAW (Software Analysis Workbench) to prove that our VHDL SHA-384 implementation is equivalent to the official Cryptol specification.

## Prerequisites (User Must Install)

| Tool | Purpose | Install |
|------|---------|---------|
| **OSS CAD Suite** | GHDL + Yosys + plugin | [Download](https://github.com/YosysHQ/oss-cad-suite-build/releases) `darwin-arm64` |
| **SAW** | Formal verification | [Download](https://github.com/GaloisInc/saw-script/releases) `macos-14-ARM64` |
| **Cryptol** | Spec language | Bundled with SAW |
| **Z3** | SMT solver | `brew install z3` or use SAW `-with-solvers` build |

**Note**: See `formal/README.md` for detailed installation instructions.

## Verification Workflow

```
┌─────────────┐     ┌─────────┐     ┌──────────┐     ┌─────────┐
│ VHDL Source │────▶│  GHDL   │────▶│  Yosys   │────▶│  JSON   │
│ sha384.vhd  │     │ analyze │     │ ghdl cmd │     │ netlist │
└─────────────┘     └─────────┘     └──────────┘     └────┬────┘
                                                          │
┌─────────────┐     ┌─────────┐     ┌──────────┐          │
│  Cryptol    │────▶│   SAW   │◀────│yosys_    │◀─────────┘
│  SHA384.cry │     │ verify  │     │import    │
└─────────────┘     └─────────┘     └──────────┘
```

## Implementation Steps

### Step 1: Create verification directory structure

```
formal/
├── cryptol/
│   └── SHA384.cry        # Copy from GaloisInc/cryptol-specs
├── scripts/
│   ├── synthesize.sh     # GHDL → Yosys → JSON
│   └── verify.saw        # SAWScript verification
├── json/
│   └── (generated)       # Yosys JSON output
└── README.md             # Setup instructions
```

### Step 2: Create synthesis script (`formal/scripts/synthesize.sh`)

```bash
#!/bin/bash
# Synthesize VHDL to Yosys JSON for SAW verification

set -e

# Analyze VHDL
ghdl -a --std=08 ../../sha384_pkg.vhd
ghdl -a --std=08 ../../sha384.vhd

# Synthesize to JSON via Yosys
yosys -m ghdl -p '
  ghdl sha384;
  prep -top sha384;
  write_json ../json/sha384.json
'

echo "Generated: formal/json/sha384.json"
```

### Step 3: Fetch Cryptol SHA-384 specification

Clone or download from: https://github.com/GaloisInc/cryptol-specs
- `Primitive/Keyless/Hash/SHA2/Specification.cry`
- `Primitive/Keyless/Hash/SHA2/Instantiations/SHA384.cry`

### Step 4: Create SAWScript (`formal/scripts/verify.saw`)

```sawscript
// Enable experimental Yosys support
enable_experimental;

// Import the VHDL (synthesized to JSON)
m <- yosys_import "json/sha384.json";

// Load Cryptol SHA-384 specification
import "cryptol/SHA384.cry";

// Define what we're verifying:
// The VHDL sha384 module should be equivalent to Cryptol's sha384 function

// Start with simpler properties:
// 1. Verify the round function in isolation
// 2. Verify message schedule computation
// 3. Verify full hash for bounded input sizes

// Example: Verify single-block hash
sha384_single_block_spec <- yosys_verify
  {{ m.sha384 }}           // VHDL module
  []                       // No preconditions
  {{ sha384_reference }}   // Cryptol reference
  []                       // No overrides
  z3;                      // SMT solver

print "SHA-384 verification complete!";
```

### Step 5: Create Makefile target

Add to project Makefile:
```makefile
# Formal verification with SAW
formal-synth:
	cd formal/scripts && ./synthesize.sh

formal-verify: formal-synth
	cd formal && saw scripts/verify.saw

formal-clean:
	rm -rf formal/json/*.json
```

## Verification Strategy

### Phase 1: Infrastructure (Get toolchain working)
1. Install prerequisites
2. Verify GHDL can analyze our VHDL
3. Verify Yosys+GHDL plugin can synthesize to JSON
4. Verify SAW can import the JSON

### Phase 2: Incremental Verification
Start with simpler properties before full equivalence:

| Property | Complexity | Description |
|----------|------------|-------------|
| Constants | Low | K[0..79] and H_INIT match spec |
| ch/maj/sigma | Low | Bitwise functions are correct |
| Single round | Medium | One compression round matches |
| Message schedule | Medium | W[t] computation is correct |
| Single block | High | Full hash of one 1024-bit block |
| Multi-block | Very High | Chained blocks with padding |

### Phase 3: Full Verification
Prove: `∀ msg. vhdl_sha384(msg) = cryptol_sha384(msg)`

## Challenges & Mitigations

| Challenge | Mitigation |
|-----------|------------|
| 80 rounds of symbolic unrolling | Start with bounded verification (1 round, 1 block) |
| State machine complexity | May need to verify combinational core separately from FSM |
| GHDL plugin availability | Document OSS CAD Suite as alternative |
| Tool installation on macOS | Provide Homebrew + manual build instructions |

## Files to Create

| File | Purpose |
|------|---------|
| `formal/README.md` | Setup and usage instructions |
| `formal/scripts/synthesize.sh` | GHDL → Yosys → JSON pipeline |
| `formal/scripts/verify.saw` | SAWScript verification |
| `formal/cryptol/` | Cryptol specs (copied from upstream) |
| `Makefile` | Add formal verification targets |

## Success Criteria

1. Toolchain runs end-to-end without errors
2. SAW can import the synthesized VHDL
3. At least one meaningful property is proven (e.g., constants match)
4. Clear documentation for reproducing the verification

## Open Questions

1. **Which implementation to verify first?**
   - Baseline `sha384.vhd` is simplest (no CSA, no unrolling)
   - Recommendation: Start with baseline

2. **What if full verification is too expensive?**
   - Fall back to bounded model checking
   - Verify components in isolation
   - Use abstraction/compositional reasoning

3. **GHDL-Yosys plugin installation**
   - May require building from source
   - OSS CAD Suite bundles everything but is large (~1GB)
