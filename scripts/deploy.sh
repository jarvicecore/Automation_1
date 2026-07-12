#!/usr/bin/env bash
#
# Deploy hook. Called once per environment by .github/workflows/_deploy.yml,
# AFTER the artifact's digest and build provenance have both been verified.
#
# The same script serves all six environments. Everything that differs between
# them arrives as configuration, never as a code branch:
#
#   $TARGET_ENV           dev | qa | stage | uat | prod | train
#   $RELEASE_TAG          e.g. v0.1.42 -- the immutable release being deployed
#   $ARTIFACT_SHA256      verified digest of dist/*.tar.gz
#   $EXTRACT_TARGET       GitHub Environment *variable*  -- where extracts land
#   $EXTRACT_CREDENTIALS  GitHub Environment *secret*    -- how to authenticate
#
# Resist the urge to add `if [ "$TARGET_ENV" = "prod" ]` special cases. The
# value of this pipeline is that prod is exercised by every lower environment
# running the identical code path.

set -euo pipefail

ENV_NAME="${1:?usage: deploy.sh <environment>}"

echo "==> Deploying ${RELEASE_TAG} to ${ENV_NAME}"
echo "    digest: ${ARTIFACT_SHA256}"
echo "    target: ${EXTRACT_TARGET:-<unset>}"

if [ -z "${EXTRACT_TARGET:-}" ]; then
  echo "::warning::EXTRACT_TARGET is not set for '${ENV_NAME}'. Set it as a GitHub"
  echo "::warning::Environment variable (Settings > Environments > ${ENV_NAME})."
fi

# Unpack the verified artifact.
workdir="$(mktemp -d)"
tar -xzf dist/*.tar.gz -C "$workdir"
echo "==> Unpacked:"
cat "$workdir"/*/BUILDINFO 2>/dev/null || true

# ---------------------------------------------------------------------------
# TODO: your real deployment goes here.
#
# For a data-extract workload this is usually one of:
#   * push extract definitions to the orchestrator for this environment
#     (Airflow / ADF / Databricks Jobs / SSIS catalogue)
#   * register the new version with the scheduler and flip the active pointer
#   * run the extract once against $EXTRACT_TARGET to prove it works
#
# Authenticate with $EXTRACT_CREDENTIALS, or better, drop it entirely and use
# the OIDC token the job already has (id-token: write is granted) to federate
# into the target platform with no long-lived secret at all.
# ---------------------------------------------------------------------------

echo "==> [stub] would deploy extracts from ${workdir} to ${EXTRACT_TARGET:-<unset>}"

echo "==> Deploy to ${ENV_NAME} complete"
