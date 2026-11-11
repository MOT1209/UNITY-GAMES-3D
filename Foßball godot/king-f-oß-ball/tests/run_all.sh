#!/usr/bin/env bash
# Runs every validation suite headless and prints a summary.
# Usage: tests/run_all.sh [path-to-godot]   (default: godot)
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
SUITES=(phase1_validation phase2_validation phase3_validation phase4_validation stadium_arena_validation
        phaseT1_validation phaseT3_validation phaseT4_validation phaseT5_validation phaseT6_validation
        phaseT7_validation phaseT8_validation phaseT9_validation phaseT10_validation phaseT11_validation
        phaseT12_validation)
failed=0
for s in "${SUITES[@]}"; do
  echo "=== $s ==="
  out=$("$GODOT" --headless --path . "res://tests/$s.tscn" 2>&1)
  code=$?
  echo "$out" | grep -E "FAIL|Validation summary|SCRIPT ERROR|Parse Error" || true
  if [ $code -ne 0 ]; then failed=$((failed+1)); echo ">>> $s FAILED (exit $code)"; fi
done
echo "Suites failed: $failed"
exit $failed
