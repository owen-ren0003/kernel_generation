#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"

fake=$(with_scratch_harness)
task_dir=$(bash "$fake/scripts/task/new-task.sh" --mode bug-track --id assignA --start-fresh | head -1)
task_id=$(basename "$task_dir")

bash "$fake/scripts/file-issue.sh" --id assignA --from "$fake/templates/issue.example.yaml"
assert_file_exists "$task_dir/issues/assignA/INFO.md"

out=$(bash "$fake/scripts/assign-issue.sh" --issue assignA --ws ws1 2>&1)
assert_contains "$out" "ws1 <- assignA"
assert_contains "$(cat "$task_dir/active-fixes.json")" '"issue_id": "assignA"'
assert_contains "$(cat "$task_dir/meta.yaml")" "ws1"

out=$(bash "$fake/scripts/release-workspace.sh" --ws ws1 --abandon 2>&1)
assert_contains "$out" "Released ws1"
assert_contains "$(cat "$task_dir/active-fixes.json")" '"available": true'

exit 0
