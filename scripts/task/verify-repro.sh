#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HARNESS_ROOT/scripts/_lib.sh"

kind="post"
task_arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pre-fix) kind="pre"; shift ;;
    --post-fix) kind="post"; shift ;;
    *) task_arg="$1"; shift ;;
  esac
done

task="${task_arg:-$(task_id)}"
[[ "$task" == /* ]] || task="$HARNESS_ROOT/state/tasks/$task"
[[ -d "$task" ]] || { echo "ERROR: task dir missing: $task" >&2; exit 2; }

key="post_fix_command"
[[ "$kind" == "pre" ]] && key="pre_fix_command"

cmd=$(python3 - "$task/meta.yaml" "$key" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
print(data.get(sys.argv[2], "") or "")
PY
)

[[ -n "$cmd" ]] || { echo "[verify] no $key configured; skipping" >&2; exit 0; }
echo "[verify] running $key"
bash -lc "$cmd"
