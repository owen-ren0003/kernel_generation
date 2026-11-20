#!/usr/bin/env bash
# run-tests.sh — Run a small set of tests on the configured target.
#
# Works for both test_env.mode = docker (e.g. .152, .32) and conda (e.g. .206).
# The same arg shape works for both modes; the script reads test_env.mode
# from config.yaml and dispatches accordingly.
#
# Usage:
#   bash scripts/run-tests.sh --ws ws1 --tests state/regression-sample.txt
#   bash scripts/run-tests.sh --ws ws1 --test "tests/x.py::test_y"
#   bash scripts/run-tests.sh --slot fix_bin --test "tests/x.py::test_y"
#   bash scripts/run-tests.sh --slot dev_reference --test "..."
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS_ROOT"
source "$HARNESS_ROOT/scripts/_lib.sh"

WS=""
SLOT=""
TESTS_FILE=""
SINGLE_TEST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ws)     WS="$2";          shift 2 ;;
    --slot)   SLOT="$2";        shift 2 ;;
    --tests)  TESTS_FILE="$2";  shift 2 ;;
    --test)   SINGLE_TEST="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Resolve which slot/dir on the target the binaries live in.
if [[ -n "$WS" ]]; then
  BIN_DIR=$(remote_bin_dir "$WS")     # dt_debug_<ws>/fix_bin (docker) or fix_bin (conda)
elif [[ -n "$SLOT" ]]; then
  BIN_DIR=$(remote_bin_dir "$SLOT")
else
  BIN_DIR=$(remote_bin_dir fix_bin)
fi

# Build the pytest argument list.
TEST_ARGS=""
if [[ -n "$SINGLE_TEST" ]]; then
  TEST_ARGS="\"$SINGLE_TEST\""
elif [[ -n "$TESTS_FILE" ]]; then
  [[ -f "$TESTS_FILE" ]] || { echo "Tests file not found: $TESTS_FILE" >&2; exit 2; }
  N=$(wc -l < "$TESTS_FILE")
  if [[ $N -gt 100 ]]; then
    echo "ERROR: $TESTS_FILE has $N tests; use run-full-suite.sh for >100 tests." >&2
    exit 2
  fi
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    TEST_ARGS="$TEST_ARGS \"$line\""
  done < "$TESTS_FILE"
else
  echo "ERROR: --test or --tests required" >&2; exit 2
fi

PIPELINE=$(read_yaml test_env.pipeline_root)
TEST_DIR=$(read_yaml test_env.flaggems_test_dir)

# Per-mode: do we set BISHENG_INSTALL_PATH explicitly, or rely on
# permanent_pipeline/scripts/setenv.bash? Both modes do the latter today.
remote_run "
  source $PIPELINE/scripts/setenv.bash 2>/dev/null
  export PATH=$BIN_DIR:\$PATH
  export BISHENG_INSTALL_PATH=$BIN_DIR
  rm -rf ~/.triton/cache/*
  cd $TEST_DIR
  pytest $TEST_ARGS --ref cpu -sv
"
