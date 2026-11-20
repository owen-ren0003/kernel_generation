#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"

fake=$(with_scratch_harness)

out=$(bash "$fake/scripts/task/new-task.sh" --mode bug-track --id smoke111 --focus "smoke" 2>&1)
rc=$?
assert_zero "$rc" "new-task should create a bug-track task"
task_dir=$(printf '%s' "$out" | head -1)
assert_file_exists "$task_dir/meta.yaml"
assert_file_exists "$task_dir/REPRODUCE.md"
assert_file_exists "$task_dir/LOG.md"
assert_file_exists "$task_dir/INTERVENTIONS.md"
assert_file_exists "$task_dir/REFLECTION.md"
assert_file_exists "$task_dir/attempts.md"
assert_file_exists "$task_dir/CONSULTATION.md"
[[ -d "$task_dir/issues" ]] || { echo "FAIL: issues/ should exist" >&2; exit 1; }

assert_contains "$(cat "$task_dir/meta.yaml")" 'mode: "bug-track"'
assert_contains "$(cat "$task_dir/meta.yaml")" 'id: "smoke111"'
assert_contains "$(cat "$task_dir/meta.yaml")" "consultation_failure_threshold: 2"
assert_contains "$(cat "$task_dir/meta.yaml")" "artifact_dir: \".local-artifacts/$(basename "$task_dir")\""
assert_contains "$(cat "$task_dir/REPRODUCE.md")" ".local-artifacts/$(basename "$task_dir")/"
[[ "$(basename "$task_dir")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-bug-smoke111$ ]] \
  || { echo "FAIL: bad task slug: $(basename "$task_dir")" >&2; exit 1; }

out2=$(bash "$fake/scripts/task/new-task.sh" --mode bug-track --id smoke111 2>&1)
rc2=$?
assert_zero "$rc2" "resume should exit 0 in Codex harness"
assert_contains "$out2" "$task_dir"

out3=$(bash "$fake/scripts/task/new-task.sh" --mode bug-track --id smoke111 --start-fresh 2>&1)
fresh_dir=$(printf '%s' "$out3" | head -1)
[[ "$fresh_dir" == "${task_dir}-2" ]] || { echo "FAIL: expected ${task_dir}-2 got $fresh_dir" >&2; exit 1; }
assert_contains "$(cat "$fresh_dir/meta.yaml")" "$(basename "$task_dir")"

bash "$fake/scripts/task/new-task.sh" --mode bogus --id whatever >/dev/null 2>&1
rc4=$?
assert_nonzero "$rc4" "unknown mode should fail"

exit 0
