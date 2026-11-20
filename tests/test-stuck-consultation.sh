#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"

fake=$(with_scratch_harness)
task_dir=$(bash "$fake/scripts/task/new-task.sh" --mode bug-track --id stuckA --focus "checkpoint test" | head -1)
checker="$fake/scripts/task/check-stuck-consultation.py"

mkdir -p "$fake/consulting/hardware"
printf '# Router\n' > "$fake/consulting/STUCK-ROUTER.md"
printf '# Synchronization\n' > "$fake/consulting/hardware/03-execution-and-synchronization.md"

cat > "$task_dir/attempts.md" <<'EOF'
# Attempts
## Attempt 1 - first hypothesis
**Outcome:** failed
EOF
out=$(python3 "$checker" "$task_dir" --mode checkpoint 2>&1)
assert_zero "$?" "one failed approach should not trigger the checkpoint"

cat >> "$task_dir/attempts.md" <<'EOF'
## Attempt 2 - second hypothesis
**Outcome:** failed
EOF
out=$(python3 "$checker" "$task_dir" --mode checkpoint 2>&1)
rc=$?
assert_nonzero "$rc" "two consecutive failed approaches should trigger the checkpoint"
assert_contains "$out" "REQUIRED: 2 consecutive approaches failed"

cat > "$task_dir/CONSULTATION.md" <<'EOF'
# Consulting Checkpoints
## Checkpoint 1
**Covers through attempt:** 2
**Obstacle class:** synchronization
**Consulted guides:** consulting/STUCK-ROUTER.md, consulting/hardware/missing.md
**Relevant guidance:** Trace the actual producer and consumer event edge.
**Next experiment:** Dump both sides of the first synchronization transformation.
EOF
out=$(python3 "$checker" "$task_dir" --mode checkpoint 2>&1)
rc=$?
assert_nonzero "$rc" "a checkpoint must not accept a missing consulting guide"
assert_contains "$out" "missing guide"

sed -i 's|consulting/hardware/missing.md|consulting/hardware/03-execution-and-synchronization.md|' "$task_dir/CONSULTATION.md"
out=$(python3 "$checker" "$task_dir" --mode checkpoint 2>&1)
assert_zero "$?" "a complete checkpoint should reset the failure streak"

cat >> "$task_dir/attempts.md" <<'EOF'
## Attempt 3 - first revised hypothesis
**Outcome:** failed
EOF
out=$(python3 "$checker" "$task_dir" --mode checkpoint 2>&1)
assert_zero "$?" "one failure after a checkpoint should not immediately retrigger"

cat >> "$task_dir/attempts.md" <<'EOF'
## Attempt 4 - second revised hypothesis
**Outcome:** failed
EOF
out=$(python3 "$checker" "$task_dir" --mode checkpoint 2>&1)
rc=$?
assert_nonzero "$rc" "two more failures should require another checkpoint"

cat >> "$task_dir/CONSULTATION.md" <<'EOF'
## Checkpoint 2
**Covers through attempt:** 4
**Obstacle class:** synchronization
**Consulted guides:** consulting/STUCK-ROUTER.md, consulting/hardware/03-execution-and-synchronization.md
**Relevant guidance:** Compare event ownership before and after the changed pass.
**Next experiment:** Isolate one event pair and verify its generated instruction order.
EOF
out=$(python3 "$checker" "$task_dir" --mode checkpoint 2>&1)
assert_zero "$?" "a second valid checkpoint should reset the second streak"

out=$(python3 "$checker" "$task_dir" --mode abandon 2>&1)
assert_zero "$?" "abandonment gate should pass after checkpoints and enough failed approaches"

cat > "$task_dir/attempts.md" <<'EOF'
# Attempts
## Attempt 1 - failed before a successful control
**Outcome:** failed
## Attempt 2 - successful control
**Outcome:** succeeded
## Attempt 3 - new failure
**Outcome:** failed
EOF
printf '# Consulting Checkpoints\n' > "$task_dir/CONSULTATION.md"
out=$(python3 "$checker" "$task_dir" --mode checkpoint 2>&1)
assert_zero "$?" "a succeeded approach should break the consecutive-failure streak"

exit 0
