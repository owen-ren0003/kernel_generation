#!/usr/bin/env bash
# scripts/_build-tracker.sh — read/write helpers for state/build-tracker/.
#
# A tracker file records what each build folder contains (commit, branch,
# build_type, timestamp) and what each bin folder on each test machine
# has deployed (source commit, source repo, deploy timestamp).
#
# One YAML file per workspace at state/build-tracker/<workspace>.yaml.
# Updated atomically via .tmp + mv so concurrent reads never see
# half-written state.
#
# This file is sourced by scripts/build-binaries.sh, scripts/deploy-binary.sh,
# scripts/pick-build-folder.sh, and any other script that needs to read or
# update the tracker. It does NOT execute anything on import.

# All paths anchored at HARNESS_ROOT. If a caller didn't set it, derive.
HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# The tracker directory is gitignored. Create on demand.
TRACKER_DIR="$HARNESS_ROOT/state/build-tracker"

# Path to one workspace's tracker file.
_tracker_path() {
  local ws=$1
  [[ -z "$ws" ]] && { echo "tracker: workspace name required" >&2; return 2; }
  echo "$TRACKER_DIR/$ws.yaml"
}

# Initialize a tracker file with the minimal skeleton if it doesn't exist.
# Idempotent.
_tracker_init() {
  local ws=$1
  local path
  path=$(_tracker_path "$ws") || return $?
  mkdir -p "$TRACKER_DIR"
  if [[ ! -f "$path" ]]; then
    cat > "$path" <<EOF
# Build tracker for workspace $ws.
# Maintained by scripts/build-binaries.sh and scripts/deploy-binary.sh.
# Schema documented in instructions/deploy-and-test.txt ("Build Tracker").
workspace: $ws
created_at: "$(date -Iseconds)"
last_updated: "$(date -Iseconds)"
builds: {}
deployments: {}
EOF
  fi
}

# tracker_record_build <ws> <repo> <build_folder> <commit> <branch> <build_type>
#   Records (or updates) a build entry. All fields required.
#   Atomic: writes to .tmp then mv-renames.
tracker_record_build() {
  local ws=$1 repo=$2 folder=$3 commit=$4 branch=$5 build_type=$6
  local path tmp
  for arg in "$ws" "$repo" "$folder" "$commit" "$branch" "$build_type"; do
    [[ -z "$arg" ]] && { echo "tracker_record_build: missing arg" >&2; return 2; }
  done
  _tracker_init "$ws"
  path=$(_tracker_path "$ws")
  tmp="$path.tmp.$$"
  python3 - "$path" "$tmp" "$repo" "$folder" "$commit" "$branch" "$build_type" <<'PY' || return $?
import sys, yaml, datetime
src, dst, repo, folder, commit, branch, build_type = sys.argv[1:8]
with open(src) as f:
    d = yaml.safe_load(f) or {}
d.setdefault("builds", {})
d["builds"].setdefault(repo, {})
d["builds"][repo][folder] = {
    "commit": commit,
    "branch": branch,
    "build_type": build_type,
    "built_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}
d["last_updated"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
with open(dst, "w") as f:
    yaml.safe_dump(d, f, sort_keys=False, default_flow_style=False)
PY
  mv "$tmp" "$path"
}

# tracker_record_deploy <ws> <machine> <bin_folder> <source_repo> <source_commit> [<source_note>]
#   Records (or updates) a deployment entry. source_note is optional
#   (used for bin-system-<descriptor> deploys to note "ticket DTS...").
tracker_record_deploy() {
  local ws=$1 machine=$2 bin_folder=$3 src_repo=$4 src_commit=$5 src_note=${6:-}
  for arg in "$ws" "$machine" "$bin_folder" "$src_repo" "$src_commit"; do
    [[ -z "$arg" ]] && { echo "tracker_record_deploy: missing arg" >&2; return 2; }
  done
  _tracker_init "$ws"
  local path tmp
  path=$(_tracker_path "$ws")
  tmp="$path.tmp.$$"
  python3 - "$path" "$tmp" "$machine" "$bin_folder" "$src_repo" "$src_commit" "$src_note" <<'PY' || return $?
import sys, yaml, datetime
src, dst, machine, bin_folder, src_repo, src_commit, src_note = sys.argv[1:8]
with open(src) as f:
    d = yaml.safe_load(f) or {}
d.setdefault("deployments", {})
d["deployments"].setdefault(machine, {})
entry = {
    "source_repo": src_repo,
    "source_commit": src_commit,
    "deployed_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}
if src_note:
    entry["source_note"] = src_note
d["deployments"][machine][bin_folder] = entry
d["last_updated"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
with open(dst, "w") as f:
    yaml.safe_dump(d, f, sort_keys=False, default_flow_style=False)
PY
  mv "$tmp" "$path"
}

# tracker_list_builds <ws> <repo>
#   Prints one line per recorded build folder:
#     <folder>\t<commit>\t<branch>\t<build_type>
tracker_list_builds() {
  local ws=$1 repo=$2
  local path
  path=$(_tracker_path "$ws") || return $?
  [[ -f "$path" ]] || return 0
  python3 - "$path" "$repo" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f) or {}
for folder, info in (d.get("builds", {}).get(sys.argv[2]) or {}).items():
    print(f"{folder}\t{info.get('commit','')}\t{info.get('branch','')}\t{info.get('build_type','')}")
PY
}

# tracker_list_deploys <ws> <machine>
#   Prints one line per deployment:
#     <bin_folder>\t<source_repo>\t<source_commit>\t<deployed_at>
tracker_list_deploys() {
  local ws=$1 machine=$2
  local path
  path=$(_tracker_path "$ws") || return $?
  [[ -f "$path" ]] || return 0
  python3 - "$path" "$machine" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f) or {}
for folder, info in (d.get("deployments", {}).get(sys.argv[2]) or {}).items():
    print(f"{folder}\t{info.get('source_repo','')}\t{info.get('source_commit','')}\t{info.get('deployed_at','')}")
PY
}
