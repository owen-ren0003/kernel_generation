#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"

fake=$(with_scratch_harness)
hook="$fake/.codex/hooks/pre_tool_use.py"
post="$fake/.codex/hooks/post_tool_use.py"
SELF="2099-01-02-bug-foo"
SIB="2099-01-01-bug-foo"
OTHER="2099-01-03-bug-bar"

mk_task() {
  local name="$1" id="$2"
  mkdir -p "$fake/state/tasks/$name/issues/foo"
  cat > "$fake/state/tasks/$name/meta.yaml" <<EOF
mode: bug-track
id: $id
status: open
in_scope_paths:
  - /tmp/ws1
max_tool_calls_per_log_entry: 2
consultation_failure_threshold: 2
min_attempts_before_give_up: 3
EOF
  : > "$fake/state/tasks/$name/LOG.md"
  printf '# Attempts\n' > "$fake/state/tasks/$name/attempts.md"
  printf '# Consulting Checkpoints\n' > "$fake/state/tasks/$name/CONSULTATION.md"
  : > "$fake/state/tasks/$name/issues/foo/INFO.md"
  : > "$fake/state/tasks/$name/issues/foo/VERDICT.md"
}
mk_task "$SELF" foo
mk_task "$SIB" foo
mk_task "$OTHER" bar
echo "$SELF" > "$fake/state/current-task"

fire() {
  local json="$1"
  (cd "$fake" && printf '%s' "$json" | CODEX_TASK_ID="$SELF" python3 "$hook" 2>/dev/null)
  echo $?
}

rc=$(fire '{"tool_name":"Bash","tool_input":{"command":"ls /tmp/ws3"}}')
assert_eq "$rc" "2" "workspace guard should block ws3"

rc=$(fire '{"tool_name":"Bash","tool_input":{"command":"ls /tmp/ws1"}}')
assert_eq "$rc" "0" "workspace guard should allow ws1"

rc=$(fire "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"state/tasks/$SIB/issues/foo/VERDICT.md\"}}")
assert_eq "$rc" "2" "prior-task firewall should block sibling VERDICT"

rc=$(fire "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"state/tasks/$SIB/issues/foo/INFO.md\"}}")
assert_eq "$rc" "0" "prior-task firewall should allow sibling INFO"

rc=$(fire "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"state/tasks/$OTHER/issues/foo/VERDICT.md\"}}")
assert_eq "$rc" "0" "prior-task firewall should allow different bug"

touch "$fake/state/tasks/$SELF/DONE"
rc=$(fire "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"state/tasks/$SIB/issues/foo/VERDICT.md\"}}")
assert_eq "$rc" "0" "DONE task should bypass firewall"
rm -f "$fake/state/tasks/$SELF/DONE"

mkdir -p "$fake/consulting/hardware"
printf '# Router\n' > "$fake/consulting/STUCK-ROUTER.md"
printf '# Synchronization\n' > "$fake/consulting/hardware/03-execution-and-synchronization.md"
cat > "$fake/state/tasks/$SELF/attempts.md" <<'EOF'
# Attempts
## Attempt 1 - first hypothesis
**Outcome:** failed
## Attempt 2 - second hypothesis
**Outcome:** failed
EOF

rc=$(fire '{"tool_name":"Bash","tool_input":{"command":"ls /tmp/ws1"}}')
assert_eq "$rc" "2" "stuck checkpoint should block ordinary tool use after two failures"

rc=$(fire '{"tool_name":"Read","tool_input":{"file_path":"consulting/STUCK-ROUTER.md"}}')
assert_eq "$rc" "0" "stuck checkpoint should allow consulting reads"

out=$(cd "$fake" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo still-stuck"}}' | CODEX_TASK_ID="$SELF" python3 "$post" 2>&1)
assert_contains "$out" "[stuck-checkpoint]" "post hook should remind immediately after the second failure"
printf '0\n' > "$fake/state/tasks/$SELF/.log-gap-counter"

cat > "$fake/state/tasks/$SELF/CONSULTATION.md" <<'EOF'
# Consulting Checkpoints
## Checkpoint 1
**Covers through attempt:** 2
**Obstacle class:** synchronization
**Consulted guides:** consulting/STUCK-ROUTER.md, consulting/hardware/03-execution-and-synchronization.md
**Relevant guidance:** Model the producer and consumer before changing waits.
**Next experiment:** Dump the producer and consumer operations at the first divergent pass.
EOF

rc=$(fire '{"tool_name":"Bash","tool_input":{"command":"ls /tmp/ws1"}}')
assert_eq "$rc" "0" "valid consultation should reopen normal tool use"

rc=$(fire "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"touch $fake/state/tasks/$SELF/NEEDS-MORE-DATA.md\"}}")
assert_eq "$rc" "2" "give-up gate should require the configured minimum failed attempts"

cat >> "$fake/state/tasks/$SELF/attempts.md" <<'EOF'
## Attempt 3 - post-consultation experiment
**Outcome:** failed
EOF
rc=$(fire "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"touch $fake/state/tasks/$SELF/NEEDS-MORE-DATA.md\"}}")
assert_eq "$rc" "0" "give-up gate should allow after consultation and the configured minimum"

(cd "$fake" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo one"}}' | CODEX_TASK_ID="$SELF" python3 "$post")
assert_eq "$(cat "$fake/state/tasks/$SELF/.log-gap-counter")" "1" "post hook increments log counter"
(cd "$fake" && printf '%s' "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$fake/state/tasks/$SELF/LOG.md\",\"new_string\":\"x\"}}" | CODEX_TASK_ID="$SELF" python3 "$post")
assert_eq "$(cat "$fake/state/tasks/$SELF/.log-gap-counter")" "0" "LOG edit resets log counter"

exit 0
