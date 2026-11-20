#!/usr/bin/env bash
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

task="${1:-}"
repo="${2:-}"
[[ -n "$task" && -n "$repo" ]] || { echo "Usage: bash scripts/check-reward-hack-review.sh <task-id> <repo-path>" >&2; exit 2; }
[[ "$task" == /* ]] || task="$HARNESS_ROOT/state/tasks/$task"
[[ -d "$task" ]] || { echo "[reward] task dir missing: $task" >&2; exit 2; }
[[ -d "$repo/.git" ]] || { echo "[reward] repo path is not a git repo: $repo" >&2; exit 2; }

diff_sha="$(git -C "$repo" diff --cached | sha256sum | awk '{print $1}')"
if [[ "$diff_sha" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
  echo "[reward] staged diff is empty; nothing to review"
  exit 0
fi

log="$task/reward-hack-reviews.log"
[[ -f "$log" ]] || touch "$log"

override="$task/reward-hack-review-overridden"
if [[ -s "$override" ]]; then
  echo "[reward] override present with rationale; allowing commit"
  exit 0
fi

python3 - "$log" "$diff_sha" <<'PY'
import sys, re
path, sha = sys.argv[1], sys.argv[2]
text = open(path).read()
blocks = re.split(r"^---\s*$", text, flags=re.M)
matches = []
for block in blocks:
    if re.search(rf"^diff_sha:\s*{re.escape(sha)}\s*$", block, re.M):
        m = re.search(r"^verdict:\s*(HACK|NOT_HACK|UNCERTAIN)\s*$", block, re.M)
        if m:
            matches.append((m.group(1), block))
if not matches:
    print(f"[reward] no review verdict found for diff_sha {sha}", file=sys.stderr)
    print("[reward] use skills/reward-hack-review.md, then append reward-hack-reviews.log", file=sys.stderr)
    raise SystemExit(2)
verdict, block = matches[-1]
if verdict != "NOT_HACK":
    print(f"[reward] verdict for {sha} is {verdict}; commit blocked", file=sys.stderr)
    print(block.strip(), file=sys.stderr)
    raise SystemExit(2)
print(f"[reward] OK: NOT_HACK for {sha}")
PY
