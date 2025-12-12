#!/bin/bash
# Setup script for SAW formal verification tools
# Downloads and installs tools locally to formal/tools/
#
# No sudo required - everything stays in the project directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAL_DIR="$(dirname "$SCRIPT_DIR")"
TOOLS_DIR="$FORMAL_DIR/tools"

# Tool versions and URLs
OSS_CAD_VERSION="2025-12-12"
OSS_CAD_FILE="oss-cad-suite-darwin-arm64-${OSS_CAD_VERSION//-/}.tgz"
OSS_CAD_URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${OSS_CAD_VERSION}/${OSS_CAD_FILE}"

SAW_VERSION="1.4"
SAW_FILE="saw-${SAW_VERSION}-macos-14-ARM64-with-solvers.tar.gz"
SAW_URL="https://github.com/GaloisInc/saw-script/releases/download/v${SAW_VERSION}/${SAW_FILE}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "SAW Formal Verification Tools Setup"
echo "=========================================="
echo ""
echo "This will download and install tools locally to:"
echo "  $TOOLS_DIR"
echo ""
echo "Tools to install:"
echo "  - OSS CAD Suite (GHDL + Yosys + plugin) ~400MB"
echo "  - SAW with solvers ~245MB"
echo ""

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo -e "${YELLOW}Warning: This script is configured for Apple Silicon (arm64)${NC}"
    echo "Detected architecture: $ARCH"
    echo "You may need to adjust the download URLs for your platform."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create tools directory
mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"

# Download and install OSS CAD Suite
echo ""
echo "Step 1/2: OSS CAD Suite"
echo "-----------------------"

if [ -d "$TOOLS_DIR/oss-cad-suite" ]; then
    echo -e "${GREEN}Already installed${NC} at $TOOLS_DIR/oss-cad-suite"
else
    echo "Downloading OSS CAD Suite..."
    curl -L --progress-bar -o "$OSS_CAD_FILE" "$OSS_CAD_URL"

    echo "Extracting..."
    tar -xzf "$OSS_CAD_FILE"
    rm "$OSS_CAD_FILE"

    echo -e "${GREEN}Installed${NC} OSS CAD Suite"
fi

# Download and install SAW
echo ""
echo "Step 2/2: SAW (Software Analysis Workbench)"
echo "--------------------------------------------"

if [ -d "$TOOLS_DIR/saw" ]; then
    echo -e "${GREEN}Already installed${NC} at $TOOLS_DIR/saw"
else
    echo "Downloading SAW v${SAW_VERSION} with solvers..."
    curl -L --progress-bar -o "$SAW_FILE" "$SAW_URL"

    echo "Extracting..."
    tar -xzf "$SAW_FILE"
    # Handle both with-solvers and without-solvers naming
    if [ -d "saw-${SAW_VERSION}-macos-14-ARM64-with-solvers" ]; then
        mv "saw-${SAW_VERSION}-macos-14-ARM64-with-solvers" saw
    elif [ -d "saw-${SAW_VERSION}-macos-14-ARM64" ]; then
        mv "saw-${SAW_VERSION}-macos-14-ARM64" saw
    fi
    rm "$SAW_FILE"

    echo -e "${GREEN}Installed${NC} SAW"
fi

# Verify installation
echo ""
echo "=========================================="
echo "Verifying Installation"
echo "=========================================="
echo ""

# Source OSS CAD Suite environment
source "$TOOLS_DIR/oss-cad-suite/environment"
export PATH="$TOOLS_DIR/saw/bin:$PATH"

echo -n "GHDL: "
if ghdl --version 2>/dev/null | head -1; then
    echo -e "  ${GREEN}OK${NC}"
else
    echo -e "  ${RED}FAILED${NC}"
fi

echo -n "Yosys: "
if yosys -V 2>/dev/null; then
    echo -e "  ${GREEN}OK${NC}"
else
    echo -e "  ${RED}FAILED${NC}"
fi

echo -n "GHDL-Yosys plugin: "
if yosys -m ghdl -p "ghdl --version" 2>/dev/null | head -1; then
    echo -e "  ${GREEN}OK${NC}"
else
    echo -e "  ${RED}FAILED${NC}"
fi

echo -n "SAW: "
if saw --version 2>/dev/null; then
    echo -e "  ${GREEN}OK${NC}"
else
    echo -e "  ${RED}FAILED${NC}"
fi

echo -n "Cryptol: "
if cryptol --version 2>/dev/null; then
    echo -e "  ${GREEN}OK${NC}"
else
    echo -e "  ${RED}FAILED${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "To use these tools, run:"
echo ""
echo "  source $TOOLS_DIR/oss-cad-suite/environment"
echo "  export PATH=\"$TOOLS_DIR/saw/bin:\$PATH\""
echo ""
echo "Or run the formal verification with:"
echo ""
echo "  make formal-verify"
echo ""
