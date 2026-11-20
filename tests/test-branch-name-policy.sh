#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"

fake=$(with_scratch_harness)
TASK="2099-01-01-bug-branch-policy"
mkdir -p "$fake/state/tasks/$TASK"
cat > "$fake/state/tasks/$TASK/meta.yaml" <<'EOF'
mode: bug-track
id: branch-policy
status: open
ai_branch_name_exceptions: []
in_scope_paths:
  - /tmp/ws1
EOF
echo "$TASK" > "$fake/state/current-task"

check_name() {
  local branch="$1"
  (cd "$fake" && CODEX_TASK_ID="$TASK" python3 scripts/check-branch-name.py "$branch" >/dev/null 2>&1)
  echo $?
}

assert_eq "$(check_name fix/runtime-counter)" "0" "neutral branch names should pass"
assert_eq "$(check_name fix/maintain-counter)" "0" "ai inside an ordinary word should pass"
assert_eq "$(check_name fix/agent-runtime)" "0" "domain terms should not be treated as attribution"
assert_eq "$(check_name bad..branch)" "2" "invalid Git branch names should fail"

for branch in \
  codex/runtime-counter \
  feature/openai-runtime \
  chatgpt/fix \
  gpt4/fix \
  claude/fix \
  anthropic/fix \
  gemini/fix \
  copilot/fix \
  aider/fix \
  codeium/fix \
  windsurf/fix \
  devin/fix \
  ai/generated-fix \
  llm/generated-fix \
  bot/generated-fix \
  assistant/generated-fix
do
  assert_eq "$(check_name "$branch")" "2" "$branch should be blocked"
done

cat > "$fake/state/tasks/$TASK/meta.yaml" <<'EOF'
mode: bug-track
id: branch-policy
status: open
ai_branch_name_exceptions:
  - branch: codex/user-authorized-name
    user_authorization: "Use codex/user-authorized-name for this branch."
in_scope_paths:
  - /tmp/ws1
EOF
assert_eq "$(check_name codex/user-authorized-name)" "0" "exact authorized name should pass"
assert_eq "$(check_name codex/different-name)" "2" "authorization must match exactly"

(cd "$fake" && CODEX_TASK_ID=/nonexistent python3 scripts/check-branch-name.py codex/user-authorized-name >/dev/null 2>&1)
assert_eq "$?" "2" "an exception should require its active task"

repo="$SCRATCH/target"
git init -q "$repo"
git -C "$repo" config user.email "harness@example.invalid"
git -C "$repo" config user.name "Harness Test"
printf 'seed\n' > "$repo/README"
git -C "$repo" add README
git -C "$repo" commit -qm seed

(cd "$fake" && CODEX_TASK_ID="$TASK" bash scripts/create-branch.sh --repo "$repo" fix/wrapper-test >/dev/null 2>&1)
assert_eq "$?" "0" "safe wrapper should create a neutral branch"
assert_eq "$(git -C "$repo" branch --show-current)" "fix/wrapper-test" "wrapper should select its branch"

(cd "$fake" && CODEX_TASK_ID="$TASK" bash scripts/create-branch.sh --repo "$repo" codex/user-authorized-name >/dev/null 2>&1)
assert_eq "$?" "0" "safe wrapper should honor an exact explicit authorization"
assert_eq "$(git -C "$repo" branch --show-current)" "codex/user-authorized-name" "wrapper should select the authorized branch"

(cd "$fake" && CODEX_TASK_ID="$TASK" bash scripts/create-branch.sh --repo "$repo" codex/not-authorized >/dev/null 2>&1)
assert_eq "$?" "2" "safe wrapper should reject an unauthorized name"
assert_eq "$(git -C "$repo" branch --show-current)" "codex/user-authorized-name" "rejected name should not change branches"

policy=$(cat "$fake/AGENTS.md")
assert_contains "$policy" "Never put an agent signature" "policy should prohibit AI attribution"
assert_contains "$policy" "The only exception is an explicit" "policy should define the sole exception"
assert_contains "$policy" "user instruction authorizing" "exception should require a user instruction"
assert_contains "$policy" "scripts/check-branch-name.py" "policy should require validation"

exit 0
