#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HARNESS_ROOT/scripts/_lib.sh"

mode="check"
task_arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --template) mode="template"; shift ;;
    *) task_arg="$1"; shift ;;
  esac
done

if [[ -n "$task_arg" ]]; then
  task="$task_arg"
else
  task="$(task_id)"
fi
[[ "$task" == /* ]] || task="$HARNESS_ROOT/state/tasks/$task"
[[ -d "$task" ]] || { echo "[critique] task dir missing: $task" >&2; exit 2; }

critique="$task/CRITIQUE.md"
if [[ "$mode" == "template" ]]; then
  cat > "$critique" <<'EOF'
# CRITIQUE

## broken_path

> What exact broken path did the diff change, and how do you know the input still reaches it?

<your answer here>

## semantic_success

> How does the diff satisfy the semantic success criterion in REPRODUCE.md?

<your answer here>

## no_test_weakening

> Did the diff skip, xfail, delete, relax, or narrow any test or accepted input? Explain.

<your answer here>

## regression_scope

> What regression command did you run, and why is it a meaningful nearby sample?

<your answer here>
EOF
  echo "[critique] template written: $critique"
  exit 0
fi

[[ -f "$critique" ]] || {
  echo "[critique] missing $critique" >&2
  echo "[critique] run: bash scripts/check-critique.sh --template" >&2
  exit 2
}

python3 - "$critique" <<'PY'
import sys, re
text = open(sys.argv[1]).read()
required = ["broken_path", "semantic_success", "no_test_weakening", "regression_scope"]
bad = []
for key in required:
    m = re.search(rf"^##\s+{re.escape(key)}\s*$([\s\S]*?)(?=^##\s+|\Z)", text, re.M)
    if not m:
        bad.append((key, "missing"))
        continue
    body = "\n".join(
        ln for ln in m.group(1).splitlines()
        if ln.strip() and not ln.lstrip().startswith(">") and "<your answer here>" not in ln
    ).strip()
    if len(body) < 40:
        bad.append((key, "too short or placeholder"))
if bad:
    for key, why in bad:
        print(f"[critique] {key}: {why}", file=sys.stderr)
    raise SystemExit(2)
print("[critique] OK")
PY
