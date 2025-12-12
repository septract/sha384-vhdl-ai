#!/bin/bash
# Synthesize SHA-384 round function VHDL to Yosys JSON for SAW formal verification
#
# Synthesizes the combinational round function (sha384_round.vhd) which SAW can verify.
# Note: SAW's Yosys support cannot handle sequential circuits (registers/flip-flops),
# so we verify the round function in isolation.
#
# Prerequisites:
#   - GHDL with LLVM or mcode backend
#   - Yosys with GHDL plugin (ghdl-yosys-plugin)
#
# Run ./setup-tools.sh first to install tools locally, or use system tools.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAL_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$FORMAL_DIR/.."
TOOLS_DIR="$FORMAL_DIR/tools"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "SHA-384 VHDL -> Yosys JSON Synthesis"
echo "=========================================="

# Source local tools if available
if [ -d "$TOOLS_DIR/oss-cad-suite" ]; then
    echo "Using local OSS CAD Suite..."
    source "$TOOLS_DIR/oss-cad-suite/environment"
fi

if [ -d "$TOOLS_DIR/saw" ]; then
    export PATH="$TOOLS_DIR/saw/bin:$PATH"
fi

# Check prerequisites
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 not found${NC}"
        echo "Run ./setup-tools.sh to install tools locally"
        exit 1
    fi
}

check_tool ghdl
check_tool yosys

# Check for GHDL plugin in Yosys (test by trying to load it)
if ! yosys -m ghdl -p "" 2>/dev/null; then
    echo -e "${YELLOW}Warning: Yosys GHDL plugin may not be available${NC}"
    echo "Run ./setup-tools.sh to install OSS CAD Suite with the plugin"
fi

echo ""
echo "Step 1: Analyzing VHDL with GHDL..."
echo "--------------------------------------"

cd "$FORMAL_DIR"

# Clean and create GHDL work library
rm -rf work
mkdir -p work

# Analyze the round function (combinational, SAW-compatible)
ghdl -a --std=08 --workdir=work sha384_round.vhd
echo -e "  ${GREEN}✓${NC} sha384_round.vhd"

echo ""
echo "Step 2: Synthesizing to JSON via Yosys..."
echo "--------------------------------------"

# Run Yosys with GHDL frontend
yosys -m ghdl -p "
    # Read VHDL via GHDL
    ghdl --std=08 --workdir=work sha384_round;

    # Prepare for synthesis
    prep -top sha384_round;

    # Flatten hierarchy and clean up for SAW
    flatten;
    clean -purge;

    # Write JSON netlist for SAW
    write_json sha384_round.json
" 2>&1 | while read line; do
    # Filter verbose output, show important messages
    if echo "$line" | grep -qE "(Error|Warning|Importing|Module|JSON)"; then
        echo "  $line"
    fi
done

if [ -f "sha384_round.json" ]; then
    echo ""
    echo -e "${GREEN}Success!${NC}"
    echo "Generated: formal/sha384_round.json"
    echo ""
    echo "JSON size: $(wc -c < "sha384_round.json" | xargs) bytes"
    echo ""
    echo "Next step: Run SAW verification with:"
    echo "  cd formal && saw verify_round.saw"
else
    echo -e "${RED}Error: JSON file not generated${NC}"
    exit 1
fi
