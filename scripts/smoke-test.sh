#!/usr/bin/env bash
#
# Post-deploy verification. Runs inside the environment's job, so it has that
# environment's secrets and variables.
#
# Keep this fast and read-only. Its job is to answer one question: "did the
# thing we just deployed actually come up?" A failure here fails the deployment,
# which is what stops a broken release from being promoted onward -- you cannot
# promote out of an environment whose deploy never went green.

set -euo pipefail

ENV_NAME="${1:?usage: smoke-test.sh <environment>}"

echo "==> Smoke testing ${ENV_NAME}"

# ---------------------------------------------------------------------------
# TODO: your real smoke test goes here. Good candidates for data extracts:
#   * the orchestrator reports the new extract version as registered
#   * a canary extract returns a non-zero row count
#   * output schema matches the contract shipped in the artifact
# ---------------------------------------------------------------------------

echo "==> [stub] smoke test passed for ${ENV_NAME}"
