#!/usr/bin/env bash
#
# The whole pipeline, on your laptop, in one command.
#
#   docker compose up -d --build
#   ./scripts/demo.sh
#
# Builds ONE artifact, then promotes that same artifact along the real promotion
# path -- dev, qa, stage, uat, prod, train -- deploying and smoke-testing each.
# Nothing is rebuilt between environments.
#
# The point is the table it prints at the end: six environments, one digest.
# That is binary promotion, and you can see it rather than take it on faith.
#
# This is the local half. The GitHub half (approval gates, CODEOWNERS, SLSA
# attestation, promotion PRs) runs on the server -- see docs/WALKTHROUGH.md.

set -euo pipefail

cd "$(dirname "$0")/.."

ENVS=(dev qa stage uat prod train)
declare -A PORT=([dev]=8081 [qa]=8082 [stage]=8083 [uat]=8084 [prod]=8085 [train]=8086)

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
rule() { printf '%s\n' "------------------------------------------------------------"; }

# --- preflight --------------------------------------------------------------
for e in "${ENVS[@]}"; do
  if ! docker inspect "secure-release-pipeline-${e}" >/dev/null 2>&1; then
    echo "Environment 'secure-release-pipeline-${e}' is not running."
    echo "Bring the rig up first:  docker compose up -d --build"
    exit 1
  fi
done

# --- build ONCE -------------------------------------------------------------
rule; bold "BUILD (once)"; rule

export BUILD_VERSION="${BUILD_VERSION:-0.1.0-demo}"
export BUILD_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"

./scripts/build.sh

ARTIFACT="$(ls dist/*.tar.gz | head -n1)"
DIGEST="$(sha256sum "$ARTIFACT" | cut -d' ' -f1)"
RELEASE_TAG="v${BUILD_VERSION}"

echo
bold "Artifact: ${ARTIFACT}"
bold "Digest:   ${DIGEST}"
echo "This exact file is the only thing that will be deployed, six times."

# --- promote along the real path -------------------------------------------
for e in "${ENVS[@]}"; do
  echo
  rule; bold "PROMOTE -> ${e}"; rule

  RELEASE_TAG="$RELEASE_TAG" \
  ARTIFACT_SHA256="$DIGEST" \
  EXTRACT_TARGET="docker://secure-release-pipeline-${e}" \
  TARGET_ENV="$e" \
    ./scripts/deploy.sh "$e"

  ARTIFACT_SHA256="$DIGEST" \
  EXTRACT_TARGET="docker://secure-release-pipeline-${e}" \
    ./scripts/smoke-test.sh "$e"
done

# --- the receipt ------------------------------------------------------------
echo
rule; bold "SIX ENVIRONMENTS, ONE DIGEST"; rule
printf '%-7s %-7s %-9s %s\n' ENV PORT VERIFIED "DIGEST RUNNING"

all_match=1
for e in "${ENVS[@]}"; do
  body="$(curl -fsS --max-time 5 "http://localhost:${PORT[$e]}/version" 2>/dev/null || echo '{}')"
  running="$(printf '%s' "$body" | sed -n 's/.*"observed_sha256"[[:space:]]*:[[:space:]]*"\([a-f0-9]*\)".*/\1/p')"
  verified="$(printf '%s' "$body" | grep -q '"self_verified":true' && echo yes || echo NO)"

  [ "$running" = "$DIGEST" ] || all_match=0
  printf '%-7s %-7s %-9s %s\n' "$e" "${PORT[$e]}" "$verified" "${running:0:32}..."
done

echo
if [ "$all_match" -eq 1 ]; then
  bold "All six environments are running the identical artifact."
  echo "Nothing was rebuilt. Prod is running the bytes dev was built from."
else
  echo "MISMATCH -- an environment is not running the promoted artifact."
  exit 1
fi

echo
echo "Look at them:"
for e in "${ENVS[@]}"; do
  echo "  ${e}:   http://localhost:${PORT[$e]}"
done
echo
echo "Now try breaking it:"
echo "  docker exec secure-release-pipeline-prod sh -c 'echo tampered >> /opt/app/artifact.tar.gz'"
echo "  docker restart secure-release-pipeline-prod && sleep 3"
echo "  ./scripts/smoke-test.sh prod   # <- must FAIL"
