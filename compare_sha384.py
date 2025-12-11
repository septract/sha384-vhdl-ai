#!/usr/bin/env python3
"""
SHA-384 Implementation Comparison Tool

Compares Python hashlib vs VHDL implementations using random test vectors.
"""

import hashlib
import os
import random
import subprocess
import sys
import argparse
from pathlib import Path


def sha384_python(data: bytes) -> str:
    """Compute SHA-384 using Python's hashlib."""
    return hashlib.sha384(data).hexdigest()


def pad_message(data: bytes) -> bytes:
    """Pad message according to SHA-384 spec."""
    msg_len = len(data)
    bit_len = msg_len * 8
    padded = data + b'\x80'
    while (len(padded) % 128) != 112:
        padded += b'\x00'
    padded += (0).to_bytes(8, 'big')
    padded += bit_len.to_bytes(8, 'big')
    return padded


def bytes_to_hex_words(data: bytes) -> list:
    """Convert bytes to list of 64-bit hex strings."""
    words = []
    for i in range(0, len(data), 8):
        word = int.from_bytes(data[i:i+8], 'big')
        words.append(f"{word:016x}")
    return words


def write_test_vectors(filepath: Path, test_cases: list):
    """Write test vectors file for VHDL - simple format, no comments."""
    with open(filepath, 'w') as f:
        # First line: number of tests
        f.write(f"{len(test_cases)}\n")

        for name, blocks, expected_hash in test_cases:
            # Number of blocks for this test
            f.write(f"{len(blocks)}\n")
            # 16 words per block
            for block in blocks:
                words = bytes_to_hex_words(block)
                for w in words:
                    f.write(f"{w}\n")
            # Expected hash (6 x 64-bit words)
            for i in range(0, 96, 16):
                f.write(f"{expected_hash[i:i+16]}\n")


def run_vhdl_test(project_dir: Path, impl: str) -> dict:
    """Run VHDL testbench and parse results."""
    if impl == "baseline":
        pkg = "sha384_pkg.vhd"
        design = "sha384.vhd"
        tb = "sha384_file_tb.vhd"
        entity = "sha384_file_tb"
    else:
        pkg = "sha384_fast_pkg.vhd"
        design = "sha384_fast.vhd"
        tb = "sha384_fast_file_tb.vhd"
        entity = "sha384_fast_file_tb"

    # Compile
    cmd = ["nvc", "-a", pkg, design, tb]
    result = subprocess.run(cmd, cwd=project_dir, capture_output=True, text=True)
    if result.returncode != 0:
        return {"error": f"Compile failed: {result.stderr}"}

    # Elaborate
    cmd = ["nvc", "-e", entity]
    result = subprocess.run(cmd, cwd=project_dir, capture_output=True, text=True)
    if result.returncode != 0:
        return {"error": f"Elaborate failed: {result.stderr}"}

    # Run
    cmd = ["nvc", "-r", entity]
    result = subprocess.run(cmd, cwd=project_dir, capture_output=True, text=True, timeout=30)

    output = result.stdout + result.stderr

    # Parse results
    results = {"passed": 0, "failed": 0, "hashes": []}
    for line in output.split('\n'):
        if "PASS" in line:
            results["passed"] += 1
        elif "FAIL" in line:
            results["failed"] += 1
        elif "Hash:" in line:
            # Extract hash from line like "Hash: abcd1234..."
            parts = line.split("Hash:")
            if len(parts) > 1:
                results["hashes"].append(parts[1].strip().lower())

    return results


def main():
    parser = argparse.ArgumentParser(description="Compare SHA-384 implementations")
    parser.add_argument("--count", type=int, default=5, help="Number of random tests")
    parser.add_argument("--max-len", type=int, default=200, help="Max message length in bytes")
    parser.add_argument("--seed", type=int, default=None, help="Random seed")
    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    project_dir = Path(__file__).parent

    print("=" * 60)
    print("SHA-384 Implementation Comparison")
    print("=" * 60)

    # Generate test cases
    test_cases = []
    print(f"\nGenerating {args.count} random test cases...")

    for i in range(args.count):
        length = random.randint(0, args.max_len)
        data = os.urandom(length)
        py_hash = sha384_python(data)
        padded = pad_message(data)
        blocks = [padded[j:j+128] for j in range(0, len(padded), 128)]

        name = f"random_{length}b"
        test_cases.append((name, blocks, py_hash))
        print(f"  Test {i}: {name} -> {py_hash[:16]}...")

    # Write test vectors
    vectors_file = project_dir / "test_vectors.txt"
    write_test_vectors(vectors_file, test_cases)
    print(f"\nWrote test vectors to {vectors_file}")

    # Check if file-based testbenches exist
    baseline_tb = project_dir / "sha384_file_tb.vhd"
    fast_tb = project_dir / "sha384_fast_file_tb.vhd"

    if not baseline_tb.exists() or not fast_tb.exists():
        print("\nFile-based testbenches not found. Creating them...")
        print("(Run this script again after testbenches are created)")
        return 1

    # Run tests
    print("\n" + "-" * 60)
    print("Running baseline sha384...")
    baseline_results = run_vhdl_test(project_dir, "baseline")
    if "error" in baseline_results:
        print(f"  ERROR: {baseline_results['error']}")
    else:
        print(f"  Passed: {baseline_results['passed']}/{args.count}")

    print("\nRunning optimized sha384_fast...")
    fast_results = run_vhdl_test(project_dir, "fast")
    if "error" in fast_results:
        print(f"  ERROR: {fast_results['error']}")
    else:
        print(f"  Passed: {fast_results['passed']}/{args.count}")

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)

    all_match = True
    for i, (name, _, py_hash) in enumerate(test_cases):
        py_ok = True  # Python is reference
        baseline_ok = i < len(baseline_results.get('hashes', [])) and baseline_results['hashes'][i] == py_hash
        fast_ok = i < len(fast_results.get('hashes', [])) and fast_results['hashes'][i] == py_hash

        status = "OK" if (baseline_ok and fast_ok) else "MISMATCH"
        if status == "MISMATCH":
            all_match = False
            print(f"Test {i} ({name}): {status}")
            print(f"  Python:   {py_hash}")
            if i < len(baseline_results.get('hashes', [])):
                print(f"  Baseline: {baseline_results['hashes'][i]}")
            if i < len(fast_results.get('hashes', [])):
                print(f"  Fast:     {fast_results['hashes'][i]}")

    if all_match and not ("error" in baseline_results or "error" in fast_results):
        print("All implementations match!")
        return 0
    else:
        print("Differences detected!")
        return 1


if __name__ == "__main__":
    sys.exit(main())
