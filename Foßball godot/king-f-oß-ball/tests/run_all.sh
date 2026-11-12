#!/usr/bin/env bash
# Runs every validation suite headless and prints a summary.
# Usage: tests/run_all.sh [path-to-godot]
#   Godot is taken from $1, else $GODOT, else `godot` on PATH.
#   Windows example: tests/run_all.sh /c/tools/godot/Godot_v4.7.2-stable_win64_console.exe
# Each suite has a hard time limit ($SUITE_TIMEOUT seconds, default 300) so a
# parse error that leaves the headless engine idle can never hang the run.
set -u
GODOT="${1:-${GODOT:-godot}}"
SUITE_TIMEOUT="${SUITE_TIMEOUT:-300}"
cd "$(dirname "$0")/.."

SUITES=(phase1_validation phase2_validation phase3_validation phase4_validation phase5_validation
        stadium_arena_validation
        phaseT1_validation phaseT3_validation phaseT4_validation phaseT5_validation phaseT6_validation
        phaseT7_validation phaseT8_validation phaseT9_validation phaseT10_validation phaseT11_validation
        phaseT12_validation phase6_integration_validation)

failed=0
total_pass=0
total_fail=0

# --- Guard 1: every tests/*_validation.tscn must be in SUITES -----------------
for f in tests/*_validation.tscn; do
  name="$(basename "$f" .tscn)"
  found=0
  for s in "${SUITES[@]}"; do [ "$s" = "$name" ] && found=1; done
  if [ $found -eq 0 ]; then
    echo ">>> $name exists in tests/ but is NOT in run_all.sh SUITES"
    failed=$((failed+1))
  fi
done

# --- Guard 2: no duplicate global class_name inside the project ---------------
dups=$(grep -rhoE --include=*.gd "^class_name[[:space:]]+[A-Za-z_][A-Za-z0-9_]*" scripts tests tools 2>/dev/null \
        | awk '{print $2}' | sort | uniq -d)
if [ -n "$dups" ]; then
  echo ">>> duplicate class_name: $dups"
  failed=$((failed+1))
else
  echo "class_name check: no duplicates"
fi

# --- Suites -------------------------------------------------------------------
for s in "${SUITES[@]}"; do
  echo "=== $s ==="
  out=$(timeout "$SUITE_TIMEOUT" "$GODOT" --headless --path . "res://tests/$s.tscn" 2>&1)
  code=$?
  echo "$out" | grep -E "FAIL|Validation summary|SCRIPT ERROR|Parse Error" || true
  summary=$(echo "$out" | grep -oE "[0-9]+ passed, [0-9]+ failed" | tail -1)
  if [ -n "$summary" ]; then
    total_pass=$((total_pass + $(echo "$summary" | awk '{print $1}')))
    total_fail=$((total_fail + $(echo "$summary" | awk '{print $3}')))
  else
    echo ">>> $s printed no summary line"
    [ $code -eq 0 ] && code=1
  fi
  if [ $code -eq 124 ]; then echo ">>> $s TIMED OUT after ${SUITE_TIMEOUT}s"; fi
  if [ $code -ne 0 ]; then failed=$((failed+1)); echo ">>> $s FAILED (exit $code)"; fi
done

echo "Checks: $total_pass passed, $total_fail failed"
echo "Suites failed: $failed"
exit $failed
