#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HARNESS_ROOT/scripts/_lib.sh"

task="${1:-$(task_id)}"
[[ "$task" == /* ]] || task="$HARNESS_ROOT/state/tasks/$task"
[[ -d "$task" ]] || { echo "ERROR: task dir missing: $task" >&2; exit 2; }

cmd=$(python3 - "$task/meta.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
print(data.get("regression_command", "") or "")
PY
)

[[ -n "$cmd" ]] || { echo "[regression] no regression_command configured; skipping" >&2; exit 0; }
echo "[regression] running regression_command"
bash -lc "$cmd"
