#!/usr/bin/env bash
# run-full-suite.sh — Run the full FlagGems suite on the configured target.
#
# Streams the pytest log into the active task's state dir as
# state/tasks/<task_id>/full-run-<TIMESTAMP>-<slot|ws>.log, where it can be
# fed to scripts/classify-failures.py.
#
# Usage:
#   bash scripts/run-full-suite.sh --slot fix_bin           # use the active fix_bin
#   bash scripts/run-full-suite.sh --slot dev_reference     # use a named preset
#   bash scripts/run-full-suite.sh --ws ws1                 # use ws1's deploy slot
#                                                           # (dt_debug_ws1 in mode=docker)
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS_ROOT"
source "$HARNESS_ROOT/scripts/_lib.sh"

WS=""
SLOT=""
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ws)     WS="$2";     shift 2 ;;
    --slot)   SLOT="$2";   shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Mass-test window guard, optional per target.
ENFORCE=$(read_yaml test_env.enforce_mass_test_window)
if [[ "$ENFORCE" == "True" || "$ENFORCE" == "true" ]]; then
  bash "$HARNESS_ROOT/scripts/time-window-check.sh" --mass
fi

if [[ -n "$WS" ]]; then
  BIN_DIR=$(remote_bin_dir "$WS")
  LABEL="$WS"
elif [[ -n "$SLOT" ]]; then
  BIN_DIR=$(remote_bin_dir "$SLOT")
  LABEL="$SLOT"
else
  BIN_DIR=$(remote_bin_dir fix_bin)
  LABEL="fix_bin"
fi

if [[ -z "$OUTPUT" ]]; then
  TASK=$(task_dir)
  mkdir -p "$TASK"
  OUTPUT="$TASK/full-run-$(date +%F-%H%M)-${LABEL}.log"
fi
mkdir -p "$(dirname "$OUTPUT")"

PIPELINE=$(read_yaml test_env.pipeline_root)
TEST_DIR=$(read_yaml test_env.flaggems_test_dir)

echo "Mass-suite run on $(read_yaml test_env.host)"
echo "  mode:    $(read_yaml test_env.mode)"
echo "  binary:  $BIN_DIR"
echo "  output:  $OUTPUT"
echo "  start:   $(date)"

remote_run "
  source $PIPELINE/scripts/setenv.bash 2>/dev/null
  export PATH=$BIN_DIR:\$PATH
  export BISHENG_INSTALL_PATH=$BIN_DIR
  rm -rf ~/.triton/cache/*
  cd $TEST_DIR
  pytest tests/ --ref cpu -v --tb=short 2>&1
" | tee "$OUTPUT"

echo
echo "  end:     $(date)"
echo "  log:     $OUTPUT  ($(wc -l < "$OUTPUT") lines)"
