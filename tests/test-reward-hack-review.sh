#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"

fake=$(with_scratch_harness)
script="$fake/scripts/check-reward-hack-review.sh"
TASK="2099-08-01-bug-synthetic"
task_dir="$fake/state/tasks/$TASK"
mkdir -p "$task_dir"
cat > "$task_dir/meta.yaml" <<EOF
mode: bug-track
id: synthetic
status: open
EOF

repo="$SCRATCH/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name test
echo "int f(){return 0;}" > "$repo/a.cc"
git -C "$repo" add a.cc
git -C "$repo" commit -q -m initial
echo "int f(){return 1;}" > "$repo/a.cc"
git -C "$repo" add a.cc
diff_sha=$(git -C "$repo" diff --cached | sha256sum | awk '{print $1}')
log="$task_dir/reward-hack-reviews.log"

out=$(bash "$script" "$TASK" "$repo" 2>&1)
rc=$?
assert_nonzero "$rc" "missing verdict should block"
assert_contains "$out" "no review verdict"

cat > "$log" <<EOF
---
diff_sha: $diff_sha
reviewed_at: 2099-08-01T01:00:00-07:00
task: $TASK
verdict: NOT_HACK
reasoning: |
  The diff changes the broken code path directly.
---
EOF
out=$(bash "$script" "$TASK" "$repo" 2>&1)
assert_zero "$?" "NOT_HACK verdict should allow"

cat >> "$log" <<EOF
---
diff_sha: $diff_sha
reviewed_at: 2099-08-01T02:00:00-07:00
task: $TASK
verdict: HACK
reasoning: |
  The diff bypasses the broken behavior.
---
EOF
out=$(bash "$script" "$TASK" "$repo" 2>&1)
rc=$?
assert_nonzero "$rc" "latest HACK verdict should block"
assert_contains "$out" "HACK"

echo "user-approved override for test" > "$task_dir/reward-hack-review-overridden"
out=$(bash "$script" "$TASK" "$repo" 2>&1)
assert_zero "$?" "non-empty override should allow"

: > "$task_dir/reward-hack-review-overridden"
out=$(bash "$script" "$TASK" "$repo" 2>&1)
rc=$?
assert_nonzero "$rc" "empty override should not allow"

rm -f "$task_dir/reward-hack-review-overridden"
git -C "$repo" reset -q
git -C "$repo" checkout -q -- a.cc
out=$(bash "$script" "$TASK" "$repo" 2>&1)
assert_zero "$?" "empty staged diff should allow"

exit 0
