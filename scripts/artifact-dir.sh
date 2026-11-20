#!/usr/bin/env bash
# Print the disposable artifact directory without creating it.
set -euo pipefail
HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HARNESS_ROOT/scripts/_lib.sh"
if [[ $# -gt 1 ]]; then
  echo "Usage: bash scripts/artifact-dir.sh [task-id]" >&2
  exit 2
fi
if [[ $# -eq 1 ]]; then
  export CODEX_TASK_ID="$1"
fi
if [[ -f "$HARNESS_ROOT/.local-artifacts/.retention/authorization.json" ]]; then
  python3 "$HARNESS_ROOT/scripts/artifact-retention.py" sweep --if-due >/dev/null ||
    echo "Warning: artifact cleanup needs attention; see state/artifact-retention/." >&2
fi
task_artifact_dir
