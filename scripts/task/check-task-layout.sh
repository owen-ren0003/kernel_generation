#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HARNESS_ROOT/scripts/_lib.sh"

task="${1:-}"
if [[ -z "$task" ]]; then
  task="$(task_id)"
fi
if [[ "$task" != /* ]]; then
  task="$HARNESS_ROOT/state/tasks/$task"
fi

[[ -d "$task" ]] || { echo "ERROR: task dir missing: $task" >&2; exit 1; }
errors=0
err() { echo "[layout] ERROR: $*" >&2; errors=$((errors + 1)); }

for f in meta.yaml REPRODUCE.md LOG.md INTERVENTIONS.md REFLECTION.md attempts.md; do
  [[ -f "$task/$f" ]] || err "missing $f"
done

python3 - "$task" <<'PY' || errors=$((errors + 1))
import sys, yaml
from pathlib import Path
task = Path(sys.argv[1])
meta = yaml.safe_load((task / "meta.yaml").read_text()) if (task / "meta.yaml").exists() else {}
required = ["mode", "id", "created_at", "status"]
missing = [k for k in required if not str(meta.get(k, "")).strip()]
if missing:
    print("[layout] ERROR: missing meta fields: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
if "consultation_failure_threshold" in meta and not (task / "CONSULTATION.md").exists():
    print("[layout] ERROR: missing CONSULTATION.md", file=sys.stderr)
    raise SystemExit(1)
if meta.get("status") == "done":
    refl = (task / "REFLECTION.md").read_text() if (task / "REFLECTION.md").exists() else ""
    body = [ln for ln in refl.splitlines() if ln.strip() and not ln.startswith("#") and "Harness changes proposed" not in ln]
    if not body:
        print("[layout] ERROR: REFLECTION.md has no non-template content", file=sys.stderr)
        raise SystemExit(1)
PY

if [[ -f "$task/REPRODUCE.md" ]]; then
  for marker in "Target Repository" "Pre-Fix Command" "Expected Failure Signature" "Semantic Success Criterion"; do
    if ! rg -q "$marker" "$task/REPRODUCE.md"; then
      err "REPRODUCE.md missing marker: $marker"
    fi
  done
fi

if (( errors > 0 )); then
  echo "[layout] $errors error(s)" >&2
  exit 1
fi
echo "[layout] OK: $(basename "$task")"
