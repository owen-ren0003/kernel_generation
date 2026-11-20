#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS_ROOT"
source "$HARNESS_ROOT/scripts/_lib.sh"

id=""
from=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) id="${2:-}"; shift 2 ;;
    --from) from="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$id" ]] || { echo "ERROR: --id required" >&2; exit 2; }
issue_dir="$(state_issue_dir "$id")"
[[ ! -e "$issue_dir" ]] || { echo "ERROR: issue already exists: $issue_dir" >&2; exit 2; }
mkdir -p "$issue_dir"

if [[ -n "$from" ]]; then
  [[ -f "$from" ]] || { echo "ERROR: not found: $from" >&2; exit 2; }
  python3 - "$from" "$issue_dir" "$id" <<'PY'
import sys, yaml, datetime
from pathlib import Path
src, dst, issue_id = sys.argv[1:]
data = yaml.safe_load(Path(src).read_text()) or {}
rep = data.get("reproducer") or {}
title = data.get("title") or issue_id
env = rep.get("env") or {}
env_lines = "\n".join(f"- {k}={v}" for k, v in env.items()) or "- (none)"
body = f"""# {issue_id} - {title}

Source: {data.get("source", "manual")}
Filed: {datetime.date.today().isoformat()}

## Description

{(data.get("description") or "").strip()}

## Reproducer

- Command: `{rep.get("command", rep.get("test", ""))}`
- Expected: {rep.get("expected", "")}
- Observed: {rep.get("observed", "")}
- Env:
{env_lines}
"""
Path(dst, "INFO.md").write_text(body)
Path(dst, "LOG.md").write_text(f"# Investigation log for {issue_id}\n\n")
PY
else
  echo "Title: " >&2
  read -r title
  echo "Reproducer command: " >&2
  read -r command
  {
    printf '# %s - %s\n\n' "$id" "$title"
    printf 'Source: manual\nFiled: %s\n\n' "$(date +%F)"
    printf '## Description\n\n(fill in)\n\n'
    printf '## Reproducer\n\n- Command: `%s`\n' "$command"
  } > "$issue_dir/INFO.md"
  printf '# Investigation log for %s\n\n' "$id" > "$issue_dir/LOG.md"
fi

echo "Filed issue at $issue_dir"
