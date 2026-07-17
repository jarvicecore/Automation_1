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
# Resist the urge to add `if [ "$TARGET_ENV" = "prod" ]` special cases. The value
# of this pipeline is that prod is exercised by every lower environment running
# the identical code path.
#
# EXTRACT_TARGET selects the backend:
#   docker://<container>   local six-environment rig (docker-compose.yml)
#   <anything else>        your real target -- see the TODO below

set -euo pipefail

ENV_NAME="${1:?usage: deploy.sh <environment>}"
RELEASE_TAG="${RELEASE_TAG:-none}"
ARTIFACT_SHA256="${ARTIFACT_SHA256:-}"
EXTRACT_TARGET="${EXTRACT_TARGET:-}"

artifact="$(ls dist/*.tar.gz 2>/dev/null | head -n1 || true)"
if [ -z "$artifact" ]; then
  echo "::error::No artifact in dist/. Nothing to deploy."
  exit 1
fi

# Never trust the caller's claim about what this artifact is. Recompute.
actual="$(sha256sum "$artifact" | cut -d' ' -f1)"
if [ -n "$ARTIFACT_SHA256" ] && [ "$actual" != "$ARTIFACT_SHA256" ]; then
  echo "::error::Digest mismatch: expected ${ARTIFACT_SHA256}, artifact on disk is ${actual}."
  exit 1
fi

echo "==> Deploying ${RELEASE_TAG} to ${ENV_NAME}"
echo "    artifact: ${artifact}"
echo "    digest:   ${actual}"
echo "    target:   ${EXTRACT_TARGET:-<unset>}"

# ---------------------------------------------------------------------------
# Backend: local docker rig
# ---------------------------------------------------------------------------
if [[ "$EXTRACT_TARGET" == docker://* ]]; then
  container="${EXTRACT_TARGET#docker://}"

  if ! docker inspect "$container" >/dev/null 2>&1; then
    echo "::error::Container '${container}' not found. Run: docker compose up -d --build"
    exit 1
  fi

  echo "--> Installing into ${container}"

  # Ship the artifact itself into the environment as well as its contents. The
  # service re-hashes it at startup to prove it is running what we think it is,
  # so the tarball is evidence, not just a delivery mechanism.
  docker cp "$artifact" "${container}:/opt/app/artifact.tar.gz"

  docker exec "$container" sh -eu -c '
    rm -rf /opt/app/next /opt/app/current
    mkdir -p /opt/app/next
    tar -xzf /opt/app/artifact.tar.gz -C /opt/app/next --strip-components=1
    mv /opt/app/next /opt/app/current
  '

  # RUNTIME is what the promotion manifest said. BUILDINFO (already inside the
  # artifact) is what the build said. The service compares them -- and compares
  # both against the bytes on disk.
  docker exec "$container" sh -eu -c "cat > /opt/app/current/RUNTIME <<EOF
environment=${ENV_NAME}
release_tag=${RELEASE_TAG}
artifact_sha256=${actual}
EOF"

  docker restart "$container" >/dev/null
  echo "==> Deployed to ${ENV_NAME} (${container})"
  exit 0
fi

# ---------------------------------------------------------------------------
# Backend: your real environment.
#
# TODO: replace this. For a data-extract workload this is usually one of:
#   * push extract definitions to the orchestrator for this environment
#     (Airflow / ADF / Databricks Jobs / SSIS catalogue)
#   * register the new version with the scheduler and flip the active pointer
#   * run the extract once against $EXTRACT_TARGET to prove it works
#
# Authenticate with $EXTRACT_CREDENTIALS -- or better, drop it entirely and use
# the OIDC token the job already has (id-token: write is granted) to federate
# into the target platform with no long-lived secret at all.
# ---------------------------------------------------------------------------
if [ -z "$EXTRACT_TARGET" ]; then
  echo "::warning::EXTRACT_TARGET is not set for '${ENV_NAME}'. Set it as a GitHub"
  echo "::warning::Environment variable (Settings > Environments > ${ENV_NAME})."
fi

echo "==> [stub] would deploy ${artifact} to ${EXTRACT_TARGET:-<unset>}"
echo "==> Deploy to ${ENV_NAME} complete"
