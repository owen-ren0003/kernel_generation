#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HARNESS_ROOT/scripts/_lib.sh"

task="${1:-$(task_id)}"
[[ "$task" == /* ]] || task="$HARNESS_ROOT/state/tasks/$task"
[[ -d "$task" ]] || { echo "ERROR: task dir missing: $task" >&2; exit 2; }

fail=0
pass() { echo "[done] OK: $*"; }
bad() { echo "[done] FAIL: $*" >&2; fail=$((fail + 1)); }

if bash "$HARNESS_ROOT/scripts/task/check-task-layout.sh" "$task" >/dev/null; then
  pass "layout"
else
  bad "layout check failed"
fi

if python3 "$HARNESS_ROOT/scripts/task/check-stuck-consultation.py" "$task" --mode checkpoint; then
  pass "no pending consulting checkpoint"
else
  bad "consulting checkpoint pending or malformed"
fi

if python3 "$HARNESS_ROOT/scripts/state-retention.py" --check --task "$(basename "$task")"; then
  pass "state contains only retained records and bookkeeping"
else
  bad "disposable state artifacts remain; preserve reproduction recipes before cleanup"
fi

if bash "$HARNESS_ROOT/scripts/task/verify-repro.sh" --post-fix "$task"; then
  pass "post-fix verification"
else
  bad "post-fix verification"
fi

if bash "$HARNESS_ROOT/scripts/task/run-regression-sample.sh" "$task"; then
  pass "regression sample"
else
  bad "regression sample"
fi

if [[ -s "$task/REFLECTION.md" ]] && rg -q '[A-Za-z0-9]' "$task/REFLECTION.md"; then
  pass "reflection present"
else
  bad "reflection missing"
fi

if (( fail > 0 )); then
  echo "[done] NOT done: $fail failure(s)" >&2
  exit 1
fi

python3 - "$task/meta.yaml" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path) as f:
    data = yaml.safe_load(f) or {}
data["status"] = "done"
with open(path, "w") as f:
    yaml.safe_dump(data, f, sort_keys=False)
PY
touch "$task/DONE"
echo "[done] DONE: $(basename "$task")"
