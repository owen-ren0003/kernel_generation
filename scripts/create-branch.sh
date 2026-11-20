#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="."

usage() {
  echo "Usage: $(basename "$0") [--repo <path>] <branch> [<start-point>]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || usage
      repo="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -ge 1 && $# -le 2 ]] || usage
branch="$1"
start_point="${2:-}"

python3 "$ROOT/scripts/check-branch-name.py" "$branch"

command=(git -C "$repo" switch -c "$branch")
if [[ -n "$start_point" ]]; then
  command+=("$start_point")
fi
exec "${command[@]}"
