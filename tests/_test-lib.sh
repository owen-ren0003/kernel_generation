#!/usr/bin/env bash
set -uo pipefail

# Scratch tasks must not inherit the invoking Codex session's active task.
unset CODEX_TASK_ID

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_BASE="${SCRATCH_BASE:-/tmp/codex-harness-tests}"
SCRATCH="$SCRATCH_BASE/$(basename "${BASH_SOURCE[1]:-test}" .sh)-$$"
mkdir -p "$SCRATCH"
TEST_FAILURES=0

_cleanup() {
  local rc=$?
  trap - EXIT
  [[ -n "${KEEP_SCRATCH:-}" ]] || rm -rf "$SCRATCH"
  if (( TEST_FAILURES > 0 )); then
    rc=1
  fi
  exit "$rc"
}
trap _cleanup EXIT

assert_eq() {
  local got="$1" want="$2" msg="${3:-}"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: ${msg:-expected '$want' got '$got'}" >&2
    TEST_FAILURES=$((TEST_FAILURES + 1))
    return 1
  fi
}

assert_zero() {
  if [[ "$1" -ne 0 ]]; then
    echo "FAIL: ${2:-expected zero exit, got $1}" >&2
    TEST_FAILURES=$((TEST_FAILURES + 1))
    return 1
  fi
}

assert_nonzero() {
  if [[ "$1" -eq 0 ]]; then
    echo "FAIL: ${2:-expected non-zero exit}" >&2
    TEST_FAILURES=$((TEST_FAILURES + 1))
    return 1
  fi
}

assert_file_exists() {
  if [[ ! -f "$1" ]]; then
    echo "FAIL: ${2:-expected file $1 to exist}" >&2
    TEST_FAILURES=$((TEST_FAILURES + 1))
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if ! grep -qF "$needle" <<< "$haystack"; then
    echo "FAIL: ${msg:-expected to contain '$needle'}" >&2
    echo "got: $haystack" >&2
    TEST_FAILURES=$((TEST_FAILURES + 1))
    return 1
  fi
}

with_scratch_harness() {
  local fake="$SCRATCH/harness"
  mkdir -p "$fake"
  cp -r "$HARNESS_ROOT"/{.codex,templates,scripts,tests,config.yaml,AGENTS.md} "$fake"/
  mkdir -p "$fake/state/tasks" "$fake/state/sessions" "$fake/state/grants"
  cd "$fake"
  git init -q
  echo "$fake"
}
