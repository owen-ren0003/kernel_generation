#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS_ROOT"
source "$HARNESS_ROOT/scripts/_lib.sh"

ws=""
abandon=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ws) ws="${2:-}"; shift 2 ;;
    --abandon) abandon=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$ws" ]] || { echo "ERROR: --ws required" >&2; exit 2; }
active="$(state_active_fixes_path)"
[[ -f "$active" ]] || echo '{}' > "$active"

python3 - "$active" "$ws" "$abandon" <<'PY'
import sys, json, datetime
from pathlib import Path
path, ws, abandon = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
p = Path(path)
state = json.loads(p.read_text()) if p.exists() and p.read_text().strip() else {}
entry = state.get(ws) or {}
if entry.get("available", True):
    print(f"{ws} is already available")
    raise SystemExit(0)
status = entry.get("status", "")
if status not in {"done", "committed", "in-master"} and not abandon:
    raise SystemExit(f"ERROR: {ws} status={status}; pass --abandon to release anyway")
state[ws] = {
    "available": True,
    "previous_issue_id": entry.get("issue_id"),
    "previous_status": status,
    "released_at": datetime.datetime.now().isoformat(timespec="seconds"),
}
p.write_text(json.dumps(state, indent=2) + "\n")
print(f"Released {ws}")
PY
