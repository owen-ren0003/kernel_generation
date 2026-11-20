#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"

cd "$HARNESS_ROOT"

PYTHONPYCACHEPREFIX="$SCRATCH/pycache" python3 -m py_compile \
  .codex/hooks/_common.py \
  .codex/hooks/pre_tool_use.py \
  .codex/hooks/post_tool_use.py \
  .codex/hooks/user_prompt_submit.py
assert_zero "$?" "hook Python files must compile"

PYTHONPYCACHEPREFIX="$SCRATCH/pycache" python3 -m py_compile \
  scripts/check-branch-name.py \
  scripts/state-retention.py \
  scripts/artifact-retention.py \
  scripts/task/check-stuck-consultation.py
assert_zero "$?" "harness Python scripts must compile"

bash -n scripts/*.sh scripts/task/*.sh
assert_zero "$?" "all shell scripts must parse"

for f in \
  instructions/build-ascend-npu-ir.txt \
  instructions/build-hivmc.txt \
  instructions/deploy-and-test.txt \
  instructions/debug-ir-files.txt \
  instructions/permanent-test-env.txt \
  scripts/build-ascend-npu-ir.sh \
  scripts/build-binaries.sh \
  scripts/deploy-binary.sh \
  scripts/run-tests.sh \
  scripts/run-full-suite.sh; do
  assert_file_exists "$HARNESS_ROOT/$f"
done

git check-ignore -q instructions/login-credentials.txt
assert_zero "$?" "real credential file must be ignored"

exit 0
