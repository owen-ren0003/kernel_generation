#!/usr/bin/env bash
# time-window-check.sh — Gate mass-suite runs to the configured local window.
#
# Usage:
#   bash scripts/time-window-check.sh --mass    # check the mass-test window
#   bash scripts/time-window-check.sh           # always passes (no enforcement)
#
# Exit codes:
#   0  inside window (or no enforcement requested)
#   3  outside window — caller must abort
set -euo pipefail

MASS=0
for arg in "$@"; do
  case "$arg" in
    --mass) MASS=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [[ $MASS -eq 0 ]]; then
  exit 0
fi

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS_ROOT"

source "$HARNESS_ROOT/scripts/_lib.sh"
START_HOUR=$(python3 -c "
import os, yaml
with open(os.environ.get('HARNESS_CFG', 'config.yaml')) as f:
    cfg = yaml.safe_load(f)
print(cfg['mass_test_window']['start_hour'])
")
END_HOUR=$(python3 -c "
import os, yaml
with open(os.environ.get('HARNESS_CFG', 'config.yaml')) as f:
    cfg = yaml.safe_load(f)
print(cfg['mass_test_window']['end_hour'])
")

NOW_HOUR=$(date +%-H)

if (( NOW_HOUR < START_HOUR || NOW_HOUR >= END_HOUR )); then
  echo "Outside mass-test window (now=${NOW_HOUR}h, allowed=${START_HOUR}h–${END_HOUR}h local time)." >&2
  echo "Run single-test debugging instead, or wait until ${START_HOUR}:00 tomorrow." >&2
  exit 3
fi

echo "Inside mass-test window (now=${NOW_HOUR}h, allowed=${START_HOUR}h–${END_HOUR}h)."
exit 0
