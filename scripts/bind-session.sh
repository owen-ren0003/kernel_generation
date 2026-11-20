#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

show=0
if [[ "${1:-}" == "--show" ]]; then
  show=1
  shift
fi

if [[ $show -eq 1 ]]; then
  if [[ -n "${CODEX_TASK_ID:-}" ]]; then
    echo "$CODEX_TASK_ID"
  elif [[ -f "$HARNESS_ROOT/state/current-task" ]]; then
    cat "$HARNESS_ROOT/state/current-task"
  else
    echo "No task bound" >&2
    exit 1
  fi
  exit 0
fi

task="${1:-}"
[[ -n "$task" ]] || { echo "Usage: bash scripts/bind-session.sh <task-id>" >&2; exit 2; }
[[ -d "$HARNESS_ROOT/state/tasks/$task" ]] || { echo "ERROR: task not found: $task" >&2; exit 2; }

mkdir -p "$HARNESS_ROOT/state/sessions/$$"
printf '%s\n' "$task" > "$HARNESS_ROOT/state/sessions/$$/current-task"
printf '%s\n' "$task" > "$HARNESS_ROOT/state/current-task"
echo "Bound current shell/session to task: $task"
echo "For child commands, you may also export CODEX_TASK_ID=$task"

# Catch up after a suspended workstation; no daemon is spawned by the harness.
if [[ -f "$HARNESS_ROOT/.local-artifacts/.retention/authorization.json" ]]; then
  python3 "$HARNESS_ROOT/scripts/artifact-retention.py" sweep --if-due >/dev/null ||
    echo "Warning: artifact cleanup needs attention; see state/artifact-retention/." >&2
fi
