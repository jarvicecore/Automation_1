#!/usr/bin/env bash
#
# Test hook. Runs on every PR and every release build.
# Exit non-zero to block the merge.

set -euo pipefail

echo "==> Running tests"
failures=0

# --- application tests ------------------------------------------------------
if command -v pytest >/dev/null 2>&1; then
  echo "--> pytest"
  PYTHONPATH=src pytest -q tests/ || failures=$((failures + 1))
else
  echo "::warning::pytest not installed -- skipping application tests."
  echo "::warning::Install with: pip install -r requirements-dev.txt"
fi

# --- pipeline self-checks ---------------------------------------------------
# These catch the two most common ways this repo breaks its own pipeline, and
# they are cheap enough to always run.

echo "--> shell scripts are syntactically valid"
for f in scripts/*.sh docker/*.sh; do
  bash -n "$f" || failures=$((failures + 1))
done

echo "--> environment manifests are well-formed"
# "yq" names two different, incompatible tools -- mikefarah/yq (Go, what the
# expression below is written for) and kislyuk/yq (a Python jq-wrapper of the
# same name). The latter doesn't error on this syntax, it just returns wrong
# values, so presence alone ("command -v yq") is not enough to trust it.
if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q mikefarah; then
  for f in environments/*.yaml; do
    yq -e 'type == "!!map"' "$f" >/dev/null || {
      echo "    ${f} is not a valid YAML mapping"
      failures=$((failures + 1))
    }
  done
else
  echo "::warning::mikefarah/yq not found on PATH -- skipping manifest checks."
  echo "::warning::(found instead: $(yq --version 2>&1 || echo 'nothing'))"
fi

if [ "$failures" -gt 0 ]; then
  echo "==> ${failures} check(s) failed"
  exit 1
fi

echo "==> All tests passed"
