#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [[ -f "$HARNESS_ROOT/config.local.yaml" ]]; then
  HARNESS_CFG="$HARNESS_ROOT/config.local.yaml"
else
  HARNESS_CFG="$HARNESS_ROOT/config.yaml"
fi
export HARNESS_ROOT HARNESS_CFG

read_yaml() {
  local key=$1
  python3 - "$HARNESS_CFG" "$key" <<'PY'
import sys, yaml
cfg_path, key = sys.argv[1], sys.argv[2]
with open(cfg_path) as f:
    data = yaml.safe_load(f) or {}
v = data
for part in key.split("."):
    if isinstance(v, dict) and part in v:
        v = v[part]
    else:
        print("", end="")
        raise SystemExit(0)
if v is None:
    print("", end="")
elif isinstance(v, (dict, list)):
    print(yaml.safe_dump(v, default_flow_style=True).strip())
else:
    print(v)
PY
}

work_dir() {
  read_yaml work_dir
}

resolve_task_id() {
  if [[ -n "${CODEX_TASK_ID:-}" ]]; then
    printf '%s\n' "$CODEX_TASK_ID"
    return 0
  fi
  if [[ -f "$HARNESS_ROOT/state/current-task" ]]; then
    local cur
    cur=$(tr -d '[:space:]' < "$HARNESS_ROOT/state/current-task" 2>/dev/null || true)
    if [[ -n "$cur" ]]; then
      printf '%s\n' "$cur"
      return 0
    fi
  fi
  read_yaml task_id
}

task_id() {
  resolve_task_id
}

task_dir() {
  local tid
  tid=$(task_id)
  [[ -n "$tid" ]] || { echo "ERROR: task id is not set" >&2; return 2; }
  echo "$HARNESS_ROOT/state/tasks/$tid"
}

state_active_fixes_path() { echo "$(task_dir)/active-fixes.json"; }
state_master_fixes_path() { echo "$(task_dir)/master-fixes.json"; }
state_issues_dir() { echo "$(task_dir)/issues"; }
state_issue_dir() { echo "$(task_dir)/issues/$1"; }

task_artifact_dir() {
  local tid configured
  tid=$(task_id)
  configured=$(task_meta_value artifact_dir)
  python3 - "$HARNESS_ROOT" "$tid" "$configured" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1]).resolve()
tid, configured = sys.argv[2:]
if not tid or tid in {".", ".."} or Path(tid).name != tid:
    raise SystemExit("ERROR: a valid task id is required")
path = Path(configured).expanduser() if configured else Path(".local-artifacts") / tid
if not path.is_absolute():
    path = root / path
path = path.resolve()
if path in {root, Path.home(), Path(path.anchor)} or path.is_relative_to(root / "state"):
    raise SystemExit("ERROR: artifact_dir must be a dedicated directory outside state/")
print(path)
PY
}

ws_path() {
  local ws=$1
  echo "$(work_dir)/$ws"
}

_subst() {
  local tpl=$1
  local pr ws
  pr=$(read_yaml test_env.pipeline_root)
  ws=${2:-}
  tpl=${tpl//\{pipeline_root\}/$pr}
  [[ -n "$ws" ]] && tpl=${tpl//\{ws_name\}/$ws}
  echo "$tpl"
}

remote_bin_dir() {
  local slot=${1:-fix_bin}
  local mode pr tpl
  mode=$(read_yaml test_env.mode)
  pr=$(read_yaml test_env.pipeline_root)
  case "$mode" in
    docker)
      if [[ "$slot" =~ ^ws[0-9]+$|^master$ ]]; then
        tpl=$(read_yaml test_env.dt_debug_template)
        echo "$(_subst "$tpl" "$slot")/fix_bin"
      else
        echo "$pr/$slot"
      fi
      ;;
    conda)
      echo "$pr/$slot"
      ;;
    *) echo "ERROR: unknown test_env.mode: $mode" >&2; return 2 ;;
  esac
}

remote_lib_dir() {
  local mode pr
  mode=$(read_yaml test_env.mode)
  pr=$(read_yaml test_env.pipeline_root)
  case "$mode" in
    conda) echo "$pr/lib" ;;
    docker) echo "" ;;
    *) echo "ERROR: unknown test_env.mode: $mode" >&2; return 2 ;;
  esac
}

remote_run() {
  local cmd=$1
  local mode host container
  mode=$(read_yaml test_env.mode)
  host=$(read_yaml test_env.host)
  container=$(read_yaml test_env.container)
  case "$mode" in
    docker)
      ssh "$host" "docker exec $container bash -c $(printf '%q' "$cmd")"
      ;;
    conda)
      ssh "$host" "bash -lc $(printf '%q' "$cmd")"
      ;;
    *) echo "ERROR: unknown test_env.mode: $mode" >&2; return 2 ;;
  esac
}

task_meta_value() {
  local key=$1
  local dir
  dir=$(task_dir)
  python3 - "$dir/meta.yaml" "$key" <<'PY'
import sys, yaml
path, key = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = yaml.safe_load(f) or {}
except FileNotFoundError:
    print("", end="")
    raise SystemExit(0)
v = data
for part in key.split("."):
    if isinstance(v, dict) and part in v:
        v = v[part]
    else:
        print("", end="")
        raise SystemExit(0)
if v is None:
    print("", end="")
elif isinstance(v, (dict, list)):
    print(yaml.safe_dump(v, default_flow_style=True).strip())
else:
    print(v)
PY
}

iso_now() {
  date -Iseconds
}
