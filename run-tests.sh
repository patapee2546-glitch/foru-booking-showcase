#!/bin/bash
# Runs the JS (Node) and Python contract tests; prints a pass/fail summary.
cd "$(dirname "$0")"
pass=0; fail=0
for f in tests/*; do
  case "$f" in
    *.js|*.cjs|*.mjs) cmd=(node "$f");;
    *.py) cmd=(python3 "$f");;
    *.sh) cmd=(bash "$f");;
    *) continue;;
  esac
  if "${cmd[@]}" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $f"; fi
done
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
