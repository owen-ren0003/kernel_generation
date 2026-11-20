#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATES="$HARNESS_ROOT/templates"
TASKS_DIR="$HARNESS_ROOT/state/tasks"

mode=""
id=""
focus=""
start_fresh=0

usage() {
  sed -n '1,80p' "$0" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) mode="${2:-}"; shift 2 ;;
    --id) id="${2:-}"; shift 2 ;;
    --focus) focus="${2:-}"; shift 2 ;;
    --start-fresh) start_fresh=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$mode" && -n "$id" ]] || usage
case "$mode" in
  bug-track|suite-run|direct-ticket) ;;
  *) echo "ERROR: unknown mode: $mode" >&2; exit 2 ;;
esac

case "$mode" in
  bug-track) slug="bug" ;;
  suite-run) slug="suite" ;;
  direct-ticket) slug="ticket" ;;
esac

id="$(echo "$id" | tr 'A-Z ' 'a-z_')"
today="$(date +%Y-%m-%d)"
new_dir="$TASKS_DIR/${today}-${slug}-${id}"

mapfile -t priors < <(find "$TASKS_DIR" -maxdepth 1 -type d -name "*-${slug}-${id}" -printf '%f\n' 2>/dev/null | sort)
if [[ ${#priors[@]} -gt 0 && $start_fresh -eq 0 ]]; then
  task="${priors[-1]}"
  printf '%s\n' "$task" > "$HARNESS_ROOT/state/current-task"
  echo "$TASKS_DIR/$task"
  echo "[new-task] resumed existing task; pass --start-fresh to create another attempt" >&2
  exit 0
fi

suffix=""
if [[ -d "$new_dir" ]]; then
  n=2
  while [[ -d "${new_dir}-${n}" ]]; do n=$((n + 1)); done
  new_dir="${new_dir}-${n}"
  suffix="-${n}"
fi

mkdir -p "$new_dir/issues"
created_at="$(date -Iseconds)"
task_id="$(basename "$new_dir")"
task_rel="state/tasks/$task_id"

sed \
  -e "s|{{MODE}}|$mode|g" \
  -e "s|{{ID}}|$id|g" \
  -e "s|{{CREATED_AT}}|$created_at|g" \
  -e "s|{{FOCUS}}|${focus//|/\\|}|g" \
  -e "s|{{TASK_DIR}}|$task_rel|g" \
  -e "s|{{TASK_ID}}|$task_id|g" \
  "$TEMPLATES/meta.yaml" > "$new_dir/meta.yaml"

if [[ ${#priors[@]} -gt 0 ]]; then
  python3 - "$new_dir/meta.yaml" "${priors[@]}" <<'PY'
import sys, yaml
path, *priors = sys.argv[1:]
with open(path) as f:
    data = yaml.safe_load(f) or {}
data["prior_attempts"] = priors
with open(path, "w") as f:
    yaml.safe_dump(data, f, sort_keys=False)
PY
fi

sed \
  -e "s|{{MODE}}|$mode|g" \
  -e "s|{{ID}}|$id|g" \
  -e "s|{{TASK_DIR}}|$task_rel|g" \
  -e "s|{{TASK_ID}}|$task_id|g" \
  "$TEMPLATES/REPRODUCE.md" > "$new_dir/REPRODUCE.md"

sed -e "s|{{TASK_DIR}}|$task_rel|g" "$TEMPLATES/attempts.md" > "$new_dir/attempts.md"
cp "$TEMPLATES/CONSULTATION.md" "$new_dir/CONSULTATION.md"

cat > "$new_dir/LOG.md" <<EOF
# LOG - $task_id

Append one ISO-8601 timestamped section per meaningful work step.

## $created_at - task created

Task created with mode=$mode id=$id focus="$focus".
EOF

cat > "$new_dir/INTERVENTIONS.md" <<EOF
# INTERVENTIONS - $task_id

| Timestamp | Trigger | User said | Codex was about to | Change after |
|---|---|---|---|---|
EOF

cat > "$new_dir/REFLECTION.md" <<EOF
# REFLECTION - $task_id

## What went right

## What went wrong

## Harness changes proposed

## Open questions
EOF

echo '{}' > "$new_dir/active-fixes.json"
echo '[]' > "$new_dir/master-fixes.json"
touch "$new_dir/reward-hack-reviews.log"

printf '%s\n' "$task_id" > "$HARNESS_ROOT/state/current-task"
echo "$new_dir"
