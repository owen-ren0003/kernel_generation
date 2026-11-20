#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"

fake=$(with_scratch_harness)

out=$(bash "$fake/scripts/task/new-task.sh" --mode bug-track --id layoutA 2>&1)
task_dir=$(printf '%s' "$out" | head -1)

bash "$fake/scripts/task/check-task-layout.sh" "$task_dir" >/dev/null 2>&1
rc=$?
assert_zero "$rc" "generated task should pass layout check"

rm "$task_dir/CONSULTATION.md"
out=$(bash "$fake/scripts/task/check-task-layout.sh" "$task_dir" 2>&1)
rc=$?
assert_nonzero "$rc" "new task metadata should require CONSULTATION.md"
assert_contains "$out" "missing CONSULTATION.md"
cp "$fake/templates/CONSULTATION.md" "$task_dir/CONSULTATION.md"

rm "$task_dir/meta.yaml"
out=$(bash "$fake/scripts/task/check-task-layout.sh" "$task_dir" 2>&1)
rc=$?
assert_nonzero "$rc" "missing meta.yaml should fail"
assert_contains "$out" "missing meta.yaml"

exit 0
