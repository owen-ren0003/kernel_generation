#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"
cd "$HARNESS_ROOT"

for path in \
  instructions/login-credentials.txt \
  instructions/login-credentials.txt.bak.example \
  config.local.yaml \
  state/tasks/example/LOG.md \
  state/build-tracker/ws1.yaml \
  .local-artifacts/example/kernel.mlir \
  build.ninja; do
  git check-ignore -q --no-index "$path"
  assert_zero "$?" "local-only path must be ignored: $path"
done
for path in state/README.md instructions/login-credentials.example.txt scripts/state-retention.py requirements.txt; do
  git check-ignore -q --no-index "$path"
  assert_nonzero "$?" "shareable path must remain trackable: $path"
done

python3 - <<'PY'
from pathlib import Path
import yaml
cfg = yaml.safe_load(Path('config.yaml').read_text())
assert cfg['task_id'] == ''
assert cfg['work_dir'].startswith('/path/to/')
assert cfg['ir_dump_dir'].startswith('.local-artifacts/')
assert cfg['failures_xlsx'].startswith('.local-artifacts/')
PY
assert_zero "$?" "shared configuration must use placeholders and external artifact paths"
exit 0
