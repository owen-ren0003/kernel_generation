#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS_ROOT"
source "$HARNESS_ROOT/scripts/_lib.sh"

issue=""
issues_csv=""
ws=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) issue="${2:-}"; shift 2 ;;
    --issues) issues_csv="${2:-}"; shift 2 ;;
    --ws) ws="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$issue" || -n "$issues_csv" ]] || { echo "ERROR: --issue or --issues required" >&2; exit 2; }
[[ -z "$ws" || -z "$issues_csv" ]] || { echo "ERROR: --ws cannot be combined with --issues" >&2; exit 2; }

if [[ -n "$issues_csv" ]]; then
  IFS=',' read -ra ids <<< "$issues_csv"
else
  ids=("$issue")
fi

issues_dir="$(state_issues_dir)"
active="$(state_active_fixes_path)"
for id in "${ids[@]}"; do
  [[ -f "$issues_dir/$id/INFO.md" ]] || { echo "ERROR: issue missing: $issues_dir/$id/INFO.md" >&2; exit 2; }
done

python3 - "$HARNESS_CFG" "$active" "$issues_dir" "$ws" "${ids[@]}" <<'PY'
import sys, json, yaml, datetime
from pathlib import Path
cfg_path, active_path, issues_dir, requested_ws, *ids = sys.argv[1:]
cfg = yaml.safe_load(Path(cfg_path).read_text()) or {}
work_dir = cfg.get("work_dir") or ""
workspaces = [w["name"] for w in cfg.get("workspaces", []) if w.get("role") != "integration"]
active = Path(active_path)
active.parent.mkdir(parents=True, exist_ok=True)
state = json.loads(active.read_text()) if active.exists() and active.read_text().strip() else {}

def free(name):
    e = state.get(name)
    return e is None or e.get("available") is True

if requested_ws:
    if requested_ws not in workspaces:
        raise SystemExit(f"ERROR: unknown workspace: {requested_ws}")
    if not free(requested_ws):
        raise SystemExit(f"ERROR: workspace busy: {requested_ws}")
    choices = [requested_ws]
else:
    choices = [w for w in workspaces if free(w)]

assigned, queued = [], []
for i, issue_id in enumerate(ids):
    if i < len(choices):
        name = choices[i]
        state[name] = {
            "available": False,
            "issue_id": issue_id,
            "status": "assigned",
            "assigned_at": datetime.datetime.now().isoformat(timespec="seconds"),
            "paused": False,
        }
        assigned.append((name, issue_id))
    else:
        queued.append(issue_id)

active.write_text(json.dumps(state, indent=2) + "\n")
meta_path = active.parent / "meta.yaml"
if assigned and meta_path.exists():
    meta = yaml.safe_load(meta_path.read_text()) or {}
    scope = list(meta.get("in_scope_paths") or [])
    for name, _issue_id in assigned:
        scope.append(str(Path(work_dir) / name) if work_dir else name)
    # Preserve order while de-duplicating.
    seen = set()
    meta["in_scope_paths"] = [x for x in scope if not (x in seen or seen.add(x))]
    meta_path.write_text(yaml.safe_dump(meta, sort_keys=False))
if assigned:
    print("Assigned:")
    for name, issue_id in assigned:
        print(f"  {name} <- {issue_id}")
if queued:
    print("Queued:")
    for issue_id in queued:
        print(f"  {issue_id}")
PY
