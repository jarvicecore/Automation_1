#!/usr/bin/env bash
#
# Test hook. Runs on every PR and every release build.
#
# Exit non-zero to block the merge. Wire your real unit/contract tests in here
# (pytest, dbt test, Great Expectations, schema-contract checks, ...).

set -euo pipefail

echo "==> Running tests"

# ---------------------------------------------------------------------------
# TODO: your real test suite goes here.
# ---------------------------------------------------------------------------

failures=0

# Placeholder checks that are genuinely worth keeping: they catch the two most
# common ways a data-extract repo breaks its own pipeline.

echo "--> Shell scripts are syntactically valid"
for f in scripts/*.sh; do
  bash -n "$f" || failures=$((failures + 1))
done

echo "--> Environment manifests are well-formed"
for f in environments/*.yaml; do
  yq -e 'type == "!!map"' "$f" > /dev/null || {
    echo "    ${f} is not a valid YAML mapping"
    failures=$((failures + 1))
  }
done

if [ "$failures" -gt 0 ]; then
  echo "==> ${failures} test(s) failed"
  exit 1
fi

echo "==> All tests passed"
