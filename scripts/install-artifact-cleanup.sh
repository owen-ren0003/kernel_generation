#!/usr/bin/env bash
# Install an idempotent per-user schedule, preserving unrelated crontab entries.
set -euo pipefail
HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -ne 0 ]]; then
  echo 'Usage: bash scripts/install-artifact-cleanup.sh' >&2
  exit 2
fi
[[ -f "$HARNESS_ROOT/.local-artifacts/.retention/authorization.json" ]] || {
  echo 'Review and authorize the retention policy first; see docs/artifact-retention.md.' >&2
  exit 1
}
command -v crontab >/dev/null
python3 - "$HARNESS_ROOT" <<'PY'
import hashlib, shlex, subprocess, sys
from pathlib import Path
root = Path(sys.argv[1])
marker = '# harness-artifact-retention-' + hashlib.sha256(str(root).encode()).hexdigest()[:12]
existing = subprocess.run(['crontab', '-l'], text=True, capture_output=True)
if existing.returncode and 'no crontab' not in existing.stderr.lower():
    raise SystemExit(existing.stderr)
lines = existing.stdout.splitlines()
lines = [line for line in lines if not line.endswith(marker)]
command = '/usr/bin/python3 ' + shlex.quote(str(root / 'scripts/artifact-retention.py')) + ' sweep >/dev/null 2>&1'
# Cron treats percent as newline even inside shell quotes.
command = command.replace('%', r'\%')
lines.append('17 */6 * * * ' + command + ' ' + marker)
subprocess.run(['crontab', '-'], input='\n'.join(lines) + '\n', text=True, check=True)
print('Installed cleanup at 00:17, 06:17, 12:17 and 18:17 local time.')
PY
if ! pgrep -x cron >/dev/null; then
  echo 'Cron is not running. Start/enable the OS cron service (WSL instructions in docs/artifact-retention.md).' >&2
fi
