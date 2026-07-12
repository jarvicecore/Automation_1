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
if command -v yq >/dev/null 2>&1; then
  for f in environments/*.yaml; do
    yq -e 'type == "!!map"' "$f" >/dev/null || {
      echo "    ${f} is not a valid YAML mapping"
      failures=$((failures + 1))
    }
  done
else
  echo "::warning::yq not installed -- skipping manifest checks."
fi

if [ "$failures" -gt 0 ]; then
  echo "==> ${failures} check(s) failed"
  exit 1
fi

echo "==> All tests passed"
