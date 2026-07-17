#!/usr/bin/env bash
#
# Post-deploy verification. Runs inside the environment's job, so it has that
# environment's secrets and variables.
#
# Its job is to answer one question: "is the thing we just deployed actually up,
# and is it the thing we think it is?" A failure here fails the deployment --
# which is what stops a broken release being promoted onward, because you cannot
# promote out of an environment whose deploy never went green.

set -euo pipefail

ENV_NAME="${1:?usage: smoke-test.sh <environment>}"
ARTIFACT_SHA256="${ARTIFACT_SHA256:-}"
EXTRACT_TARGET="${EXTRACT_TARGET:-}"
SMOKE_URL="${SMOKE_URL:-}"

echo "==> Smoke testing ${ENV_NAME}"

# Work out where to probe. The local docker rig publishes each environment on a
# fixed port; a real deployment would set SMOKE_URL (or ENVIRONMENT_URL).
if [ -z "$SMOKE_URL" ] && [[ "$EXTRACT_TARGET" == docker://* ]]; then
  case "$ENV_NAME" in
    dev)   SMOKE_URL='http://localhost:8081' ;;
    qa)    SMOKE_URL='http://localhost:8082' ;;
    stage) SMOKE_URL='http://localhost:8083' ;;
    uat)   SMOKE_URL='http://localhost:8084' ;;
    prod)  SMOKE_URL='http://localhost:8085' ;;
    train) SMOKE_URL='http://localhost:8086' ;;
  esac
fi

if [ -z "$SMOKE_URL" ]; then
  echo "::warning::No SMOKE_URL for '${ENV_NAME}'. Skipping HTTP checks."
  echo "==> [stub] smoke test passed for ${ENV_NAME}"
  exit 0
fi

echo "    probing ${SMOKE_URL}"

# 1. Liveness. Give the service a moment to come up after the restart.
for i in $(seq 1 30); do
  if curl -fsS --max-time 3 "${SMOKE_URL}/healthz" >/dev/null 2>&1; then
    echo "--> healthz ok (after ${i}s)"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "::error::${ENV_NAME} did not become healthy within 30s."
    exit 1
  fi
  sleep 1
done

# 2. Identity. /version returns 409 if the service cannot prove that the bytes it
#    is running match the digest the promotion recorded. This is the check that
#    makes binary promotion mean something: a swapped artifact fails the deploy
#    rather than quietly serving traffic.
code="$(curl -sS -o /tmp/version.json -w '%{http_code}' --max-time 5 "${SMOKE_URL}/version")"
cat /tmp/version.json
echo

if [ "$code" != "200" ]; then
  echo "::error::${ENV_NAME} failed provenance self-check (/version returned ${code})."
  echo "::error::The bytes running there are not the bytes the pipeline promoted."
  exit 1
fi
echo "--> provenance self-check ok"

# 3. The digest must be the one we meant to deploy -- not merely self-consistent.
#    (A service could be internally consistent about the WRONG release.)
if [ -n "$ARTIFACT_SHA256" ]; then
  running="$(sed -n 's/.*"observed_sha256"[[:space:]]*:[[:space:]]*"\([a-f0-9]*\)".*/\1/p' /tmp/version.json)"
  if [ "$running" != "$ARTIFACT_SHA256" ]; then
    echo "::error::${ENV_NAME} is running ${running:-<unknown>}, expected ${ARTIFACT_SHA256}."
    exit 1
  fi
  echo "--> running the expected digest"
fi

# 4. The extract still satisfies its schema contract. /extract returns 422 if not.
if ! curl -fsS --max-time 5 "${SMOKE_URL}/extract" >/dev/null; then
  echo "::error::${ENV_NAME} extract failed its schema contract."
  exit 1
fi
echo "--> extract contract ok"

echo "==> Smoke test passed for ${ENV_NAME}"
