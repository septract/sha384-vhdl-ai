# SHA-384 VHDL Project Makefile
# Requires: nvc (VHDL simulator), python3

.PHONY: all test test-quick test-baseline test-fast test-fast8 test-pipeline test-multi \
        synth-check formal-synth formal-verify formal-clean clean help

# Default target
all: test

#------------------------------------------------------------------------------
# Test targets
#------------------------------------------------------------------------------

# Full test suite (all implementations, NIST vectors, boundary tests, random)
test:
	python3 compare_sha384.py --count 10 --max-len 500

# Quick verification (fewer random tests)
test-quick:
	python3 compare_sha384.py --quick

# Test individual implementations
test-baseline:
	nvc -a sha384_pkg.vhd sha384.vhd sha384_tb.vhd && \
	nvc -e sha384_tb && \
	nvc -r sha384_tb

test-fast:
	nvc -a sha384_fast_pkg.vhd sha384_fast.vhd sha384_fast_tb.vhd && \
	nvc -e sha384_fast_tb && \
	nvc -r sha384_fast_tb

test-fast8:
	nvc -a sha384_fast_pkg.vhd sha384_fast8.vhd sha384_fast8_file_tb.vhd && \
	nvc -e sha384_fast8_file_tb && \
	nvc -r sha384_fast8_file_tb

test-pipeline:
	nvc -a sha384_fast_pkg.vhd sha384_pipeline.vhd sha384_pipeline_file_tb.vhd && \
	nvc -e sha384_pipeline_file_tb && \
	nvc -r sha384_pipeline_file_tb

test-multi:
	nvc -a sha384_fast_pkg.vhd sha384_pipeline.vhd sha384_multi.vhd sha384_multi_file_tb.vhd && \
	nvc -e sha384_multi_file_tb && \
	nvc -r sha384_multi_file_tb

# Test all implementations individually (useful for debugging)
test-all: test-baseline test-fast test-fast8 test-pipeline test-multi

#------------------------------------------------------------------------------
# Synthesis check (uses NVC elaboration to catch synthesis issues)
#------------------------------------------------------------------------------

synth-check:
	@echo "Checking synthesizability..."
	@echo -n "  sha384 (baseline): " && \
		nvc -a sha384_pkg.vhd sha384.vhd 2>/dev/null && \
		nvc -e sha384 2>/dev/null && echo "OK" || echo "FAILED"
	@rm -rf work 2>/dev/null || true
	@echo -n "  sha384_fast (4x): " && \
		nvc -a sha384_fast_pkg.vhd sha384_fast.vhd 2>/dev/null && \
		nvc -e sha384_fast 2>/dev/null && echo "OK" || echo "FAILED"
	@rm -rf work 2>/dev/null || true
	@echo -n "  sha384_fast8 (8x): " && \
		nvc -a sha384_fast_pkg.vhd sha384_fast8.vhd 2>/dev/null && \
		nvc -e sha384_fast8 2>/dev/null && echo "OK" || echo "FAILED"
	@rm -rf work 2>/dev/null || true
	@echo -n "  sha384_pipeline: " && \
		nvc -a sha384_fast_pkg.vhd sha384_pipeline.vhd 2>/dev/null && \
		nvc -e sha384_pipeline 2>/dev/null && echo "OK" || echo "FAILED"
	@rm -rf work 2>/dev/null || true
	@echo -n "  sha384_multi (4 cores): " && \
		nvc -a sha384_fast_pkg.vhd sha384_pipeline.vhd sha384_multi.vhd 2>/dev/null && \
		nvc -e sha384_multi 2>/dev/null && echo "OK" || echo "FAILED"
	@rm -rf work 2>/dev/null || true

#------------------------------------------------------------------------------
# Verify constants against FIPS 180-4 (no simulation needed)
#------------------------------------------------------------------------------

verify-constants:
	python3 compare_sha384.py --skip-vhdl

#------------------------------------------------------------------------------
# Formal Verification with SAW
#------------------------------------------------------------------------------

# Install SAW tools locally (no sudo required, ~600MB download)
formal-setup:
	@echo "Setting up SAW formal verification tools..."
	cd formal/scripts && chmod +x setup-tools.sh && ./setup-tools.sh

# Synthesize VHDL to Yosys JSON for SAW
formal-synth:
	@echo "Synthesizing VHDL to JSON for SAW..."
	cd formal/scripts && chmod +x synthesize.sh && ./synthesize.sh

# Run SAW formal verification
formal-verify: formal-synth
	@echo "Running SAW formal verification..."
	@if [ -d formal/tools/saw ]; then \
		export PATH="$$PWD/formal/tools/saw/bin:$$PATH"; \
	fi; \
	if [ -d formal/tools/oss-cad-suite ]; then \
		source formal/tools/oss-cad-suite/environment; \
	fi; \
	cd formal && saw verify_round.saw

# Clean formal verification artifacts (keeps tools)
formal-clean:
	rm -rf formal/*.json formal/work

# Remove downloaded tools (large, ~600MB)
formal-clean-tools:
	rm -rf formal/tools

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------

clean: formal-clean
	rm -rf work
	rm -f *.cf *.o
	rm -f test_vectors.txt

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

help:
	@echo "SHA-384 VHDL Project"
	@echo ""
	@echo "Test targets:"
	@echo "  make test          - Full test suite (recommended)"
	@echo "  make test-quick    - Quick verification"
	@echo "  make test-baseline - Test baseline implementation only"
	@echo "  make test-fast     - Test 4x unrolled implementation"
	@echo "  make test-fast8    - Test 8x unrolled implementation"
	@echo "  make test-pipeline - Test pipelined implementation"
	@echo "  make test-multi    - Test multi-core implementation"
	@echo "  make test-all      - Run all individual tests"
	@echo ""
	@echo "Other targets:"
	@echo "  make synth-check      - Check all designs elaborate (synthesis check)"
	@echo "  make verify-constants - Verify K/H constants against FIPS 180-4"
	@echo "  make clean            - Remove generated files"
	@echo "  make help             - Show this help"
	@echo ""
	@echo "Formal verification with SAW:"
	@echo "  make formal-setup     - Download tools locally (~600MB, no sudo)"
	@echo "  make formal-synth     - Synthesize VHDL to Yosys JSON"
	@echo "  make formal-verify    - Run SAW formal verification"
	@echo "  make formal-clean     - Clean verification artifacts"
	@echo "  make formal-clean-tools - Remove downloaded tools"
