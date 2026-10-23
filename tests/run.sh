#!/usr/bin/env bash
# Run every tests/test_*.sh in its own process. Usage: bash tests/run.sh [name-filter]
# Needs only bash + git (jq is used for JSON assertions when installed).
cd "$(dirname "$0")" || exit 1
total_fail=0
for t in test_*.sh; do
  case $t in *"${1:-}"*) ;; *) continue ;; esac
  echo "== $t"
  "${BASH:-bash}" "$t" || total_fail=$((total_fail + 1))
done
if [ "$total_fail" -eq 0 ]; then echo "ALL TEST FILES PASSED"; else
  echo "$total_fail test file(s) FAILED"
  exit 1
fi
