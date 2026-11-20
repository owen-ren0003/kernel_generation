#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

passed=0
failed=0
for t in tests/test-*.sh; do
  [[ -f "$t" ]] || continue
  name="$(basename "$t" .sh)"
  printf '%-42s' "$name"
  if out="$(bash "$t" 2>&1)"; then
    echo "PASS"
    passed=$((passed + 1))
  else
    echo "FAIL"
    printf '%s\n' "$out" | sed 's/^/    /'
    failed=$((failed + 1))
  fi
done

echo
echo "tests passed=$passed failed=$failed"
(( failed > 0 )) && exit 1
exit 0
