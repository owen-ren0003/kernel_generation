#!/usr/bin/env bash
# run-order-sensitivity-test.sh — detect order-dependent test regressions.
#
# Why this exists: the SDPA fix (master commit 6d3342d, rolled back
# 2026-05-04) passed every individual test in our 8-test regression set
# yet regressed clamp from 1,836 PASS to 0 PASS in the FULL suite. The
# discrepancy was order-dependent: clamp ran AFTER an SDPA test that
# left bad state behind (cache, NPU, or pytest-process). Catching this
# class of regression with the existing run-tests.sh required spotting
# that it was order-dependent and re-running with the right shape — by
# which point the fix was already master-integrated.
#
# This script runs the same tests TWICE:
#
#   Mode A — each test in its own pytest invocation with fresh
#            ~/.triton/cache. The "gold standard": isolated, clean.
#   Mode B — all tests in ONE pytest invocation with cache cleared once
#            at the start. The "realistic" execution: shared state
#            between tests, just like the full suite does.
#
# A test passing Mode A but failing Mode B is an order-dependent
# regression. The script exits non-zero if ANY such divergence appears,
# letting the master-maintainer use it as a quality gate.
#
# Usage:
#   bash scripts/run-order-sensitivity-test.sh --ws ws1 --tests state/regression-sample.txt
#   bash scripts/run-order-sensitivity-test.sh --slot fix_bin --tests path/to/tests.txt
#   bash scripts/run-order-sensitivity-test.sh --ws master --tests state/tasks/2026-04-30-flaggems-206-run/regression-sample.txt
#
# Exit codes:
#   0 — all tests pass in BOTH modes (no order-dependence). Safe to integrate.
#   2 — any test passes Mode A but fails Mode B (order-dependent regression).
#   3 — any test fails Mode A (test is broken regardless of order — pre-existing).
#       Triage before re-running this script.
#   4 — script error (bad args, ssh failure, etc).
#
# Output: a report at /tmp/order-sensitivity-<timestamp>.log with full
# pytest output for each mode + a summary table.
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS_ROOT"
source "$HARNESS_ROOT/scripts/_lib.sh"

WS=""
SLOT=""
TESTS_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ws)    WS="$2";    shift 2 ;;
    --slot)  SLOT="$2";  shift 2 ;;
    --tests) TESTS_FILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 4 ;;
  esac
done
[[ -n "$TESTS_FILE" ]] || { echo "ERROR: --tests <file> required" >&2; exit 4; }
[[ -f "$TESTS_FILE" ]] || { echo "ERROR: $TESTS_FILE not found" >&2; exit 4; }

# Resolve which slot/dir on the target the binaries live in.
if [[ -n "$WS" ]]; then
  BIN_DIR=$(remote_bin_dir "$WS")
elif [[ -n "$SLOT" ]]; then
  BIN_DIR=$(remote_bin_dir "$SLOT")
else
  BIN_DIR=$(remote_bin_dir fix_bin)
fi

PIPELINE=$(read_yaml test_env.pipeline_root)
TEST_DIR=$(read_yaml test_env.flaggems_test_dir)

# Build TEST array.
TESTS=()
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  TESTS+=("$line")
done < "$TESTS_FILE"
N=${#TESTS[@]}
[[ $N -gt 0 ]] || { echo "ERROR: tests file has no entries" >&2; exit 4; }
[[ $N -le 30 ]] || { echo "ERROR: order-sensitivity test is for small batches (≤30); got $N" >&2; exit 4; }

TS=$(date +%Y%m%d-%H%M%S)
REPORT="/tmp/order-sensitivity-$TS.log"
echo "================================================================" | tee "$REPORT"
echo "Order-sensitivity test — $TS" | tee -a "$REPORT"
echo "Slot: $BIN_DIR" | tee -a "$REPORT"
echo "Tests file: $TESTS_FILE ($N tests)" | tee -a "$REPORT"
echo "================================================================" | tee -a "$REPORT"

# ---------------------------------------------------------------------
# Mode A: each test in its own pytest invocation with fresh cache.
# ---------------------------------------------------------------------
declare -A MODE_A
echo "" | tee -a "$REPORT"
echo "=== Mode A — isolated runs (fresh cache, fresh pytest per test)" | tee -a "$REPORT"
for t in "${TESTS[@]}"; do
  echo "  -> $t" | tee -a "$REPORT"
  result=$(remote_run "
    source $PIPELINE/scripts/setenv.bash 2>/dev/null
    export PATH=$BIN_DIR:\$PATH
    export BISHENG_INSTALL_PATH=$BIN_DIR
    rm -rf ~/.triton/cache/*
    cd $TEST_DIR
    timeout 240 pytest \"$t\" --ref cpu -sv 2>&1 | grep -E '^(PASSED|FAILED|ERROR)|passed|failed|errored' | tail -3
  " 2>&1 || true)
  echo "$result" >> "$REPORT"
  if echo "$result" | grep -qE 'PASSED|1 passed'; then
    MODE_A[$t]="PASS"
  else
    MODE_A[$t]="FAIL"
  fi
  echo "     mode A: ${MODE_A[$t]}" | tee -a "$REPORT"
done

# Build pytest arg list for Mode B (one shell-quoted token per test).
TEST_ARGS=""
for t in "${TESTS[@]}"; do
  TEST_ARGS="$TEST_ARGS \"$t\""
done

# ---------------------------------------------------------------------
# Mode B: all tests in ONE pytest invocation. Cache cleared once at start.
# ---------------------------------------------------------------------
echo "" | tee -a "$REPORT"
echo "=== Mode B — single pytest invocation, shared state" | tee -a "$REPORT"
mode_b_output=$(remote_run "
  source $PIPELINE/scripts/setenv.bash 2>/dev/null
  export PATH=$BIN_DIR:\$PATH
  export BISHENG_INSTALL_PATH=$BIN_DIR
  rm -rf ~/.triton/cache/*
  cd $TEST_DIR
  timeout $((240 * N)) pytest $TEST_ARGS --ref cpu -sv 2>&1
" 2>&1 || true)
echo "$mode_b_output" >> "$REPORT"

declare -A MODE_B
# classify_mode_b_status TESTNAME OUTPUT
#
# Returns (via stdout) PASS / FAIL / UNKNOWN for a single test in the
# combined Mode-B pytest output.
#
# Why this is non-trivial: pytest with -sv on FlagGems_Ascend emits
# the test status on a DIFFERENT line from the test nodeid whenever
# the kernel prints a GEMS marker. The raw stream looks like:
#
#   tests/test_foo.py::test_bar[params] GEMS_ASCEND FOO
#   GEMS BAR
#   PASSED
#   tests/test_foo.py::test_baz[params] GEMS BAZ
#   PASSED
#
# A single-line `grep "<test>.*PASSED"` therefore mis-classifies these
# as UNKNOWN, which the verdict logic then upgrades to
# "MISSING IN MODE B (cascade or skip)" and exits 2 spuriously.
#
# Strategy: scan line-by-line with awk. When a line begins with the
# test nodeid (followed by either whitespace or end-of-line, so we
# don't accidentally match a parameter-prefix superset), enter a
# "looking" state. Within the next LOOKAHEAD lines, the first line
# that is exactly "PASSED" / "FAILED" / "ERROR" (with optional
# trailing whitespace) — or a line ending in PASSED / FAILED (the
# same-line case) — settles the verdict. Encountering another test
# nodeid before a verdict line means the verdict is missing.
classify_mode_b_status() {
  local test_name="$1"
  local output="$2"
  awk -v target="$test_name" '
    function is_status_line(s,    t) {
      # Strip trailing whitespace.
      t = s
      sub(/[[:space:]]+$/, "", t)
      # Match a bare verdict (e.g. "PASSED") or a verdict at end of
      # line preceded by whitespace (e.g. "GEMS FOO PASSED" or the
      # legacy same-line "<nodeid> PASSED").
      if (t == "PASSED" || t == "FAILED" || t == "ERROR") return 1
      if (t ~ /[[:space:]]PASSED$/ || t ~ /[[:space:]]FAILED$/ || t ~ /[[:space:]]ERROR$/) return 1
      return 0
    }
    function extract_status(s,    t) {
      t = s
      sub(/[[:space:]]+$/, "", t)
      if (t ~ /PASSED$/) return "PASS"
      if (t ~ /FAILED$/) return "FAIL"
      if (t ~ /ERROR$/)  return "FAIL"
      return ""
    }
    # Is THIS line the start of a (possibly different) test nodeid?
    function is_nodeid_line(s) {
      return (s ~ /^tests\/[^[:space:]]+::/)
    }
    BEGIN { looking = 0; verdict = "UNKNOWN"; lookahead = 0 }
    {
      line = $0
      # Strip CR from any DOS line endings.
      sub(/\r$/, "", line)
      if (looking) {
        # If the current line itself is a new test nodeid (and not our
        # target re-appearing — pytest does not repeat nodeids in -sv
        # output), the previous test had no verdict line; abort the
        # current search and let the new line re-trigger detection.
        if (is_nodeid_line(line) && index(line, target " ") != 1 && line != target) {
          looking = 0
          lookahead = 0
        } else {
          if (is_status_line(line)) {
            v = extract_status(line)
            if (v != "") { verdict = v; exit }
          }
          lookahead++
          if (lookahead > 20) { looking = 0; lookahead = 0 }
        }
      }
      # Trigger: line begins with target nodeid. Accept either an exact
      # match (legacy "<nodeid> PASSED" same-line) or "<nodeid> <stuff>"
      # (modern multi-line with GEMS marker on the same line as the
      # nodeid, verdict on a later line). Use prefix-with-boundary to
      # avoid matching a longer nodeid that happens to start with this
      # one (e.g. "...shape0" matching "...shape0_extra").
      if (line == target || index(line, target " ") == 1) {
        # Check same-line verdict first (covers legacy
        # "<nodeid> PASSED" and the new "<nodeid> GEMS FOO PASSED").
        v = extract_status(line)
        if (v != "") { verdict = v; exit }
        looking = 1
        lookahead = 0
      }
    }
    END { print verdict }
  ' <<< "$output"
}

for t in "${TESTS[@]}"; do
  status=$(classify_mode_b_status "$t" "$mode_b_output")
  MODE_B[$t]="$status"
done

# ---------------------------------------------------------------------
# Compare and summarize.
# ---------------------------------------------------------------------
echo "" | tee -a "$REPORT"
echo "================================================================" | tee -a "$REPORT"
echo "Summary" | tee -a "$REPORT"
echo "================================================================" | tee -a "$REPORT"
printf "%-90s %-8s %-8s %s\n" "TEST" "MODE_A" "MODE_B" "VERDICT" | tee -a "$REPORT"
echo "------------------------------------------------------------------------------------------------" | tee -a "$REPORT"

ord_dep=0
broke_a=0
both_fail=0
both_pass=0
for t in "${TESTS[@]}"; do
  a="${MODE_A[$t]}"; b="${MODE_B[$t]}"
  if [[ "$a" == "PASS" && "$b" == "PASS" ]]; then
    verdict="ok"
    both_pass=$((both_pass+1))
  elif [[ "$a" == "FAIL" ]]; then
    verdict="PRE-EXISTING (broke in Mode A)"
    broke_a=$((broke_a+1))
  elif [[ "$a" == "PASS" && "$b" == "FAIL" ]]; then
    verdict="ORDER-DEPENDENT REGRESSION"
    ord_dep=$((ord_dep+1))
  elif [[ "$a" == "PASS" && "$b" == "UNKNOWN" ]]; then
    verdict="MISSING IN MODE B (cascade or skip)"
    ord_dep=$((ord_dep+1))
  else
    verdict="$a/$b unexpected"
    both_fail=$((both_fail+1))
  fi
  printf "%-90s %-8s %-8s %s\n" "$t" "$a" "$b" "$verdict" | tee -a "$REPORT"
done

echo "" | tee -a "$REPORT"
echo "Both PASS: $both_pass / $N" | tee -a "$REPORT"
echo "Order-dependent regressions: $ord_dep" | tee -a "$REPORT"
echo "Pre-existing failures (broke in Mode A): $broke_a" | tee -a "$REPORT"
echo "Other unexpected: $both_fail" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"
echo "Full report at $REPORT" | tee -a "$REPORT"

if [[ $broke_a -gt 0 ]]; then
  echo "" | tee -a "$REPORT"
  echo "EXIT 3 — at least one test fails IN ISOLATION (Mode A). Triage these first; they are not order-dependent regressions but pre-existing breakage." | tee -a "$REPORT"
  exit 3
fi
if [[ $ord_dep -gt 0 ]]; then
  echo "" | tee -a "$REPORT"
  echo "EXIT 2 — order-dependent regression(s) detected. DO NOT integrate to master." | tee -a "$REPORT"
  exit 2
fi
echo "" | tee -a "$REPORT"
echo "EXIT 0 — all tests pass in both modes. Safe for master integration with respect to order-dependence." | tee -a "$REPORT"
exit 0
