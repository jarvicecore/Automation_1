#!/usr/bin/env sh
#
# The environment idles until something is deployed into it.
#
# "No release deployed" is a real, legitimate state -- a freshly provisioned
# environment has nothing in it. Modelling that honestly (rather than baking the
# app into the image) is what makes the local rig a fair test of the pipeline.

set -eu

echo "[${ENV_NAME:-unknown}] environment up, waiting for a deployment..."

while [ ! -f /opt/app/current/app/main.py ]; do
  sleep 2
done

echo "[${ENV_NAME:-unknown}] release detected, starting service"
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --log-level warning
