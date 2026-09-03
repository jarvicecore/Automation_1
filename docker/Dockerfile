# The ENVIRONMENT image, not the application image.
#
# This container is a stand-in for a long-lived deployment target (a VM, a pod, an
# extract host). It is built once and then sits there. It contains the runtime and
# the pinned dependencies -- but NO application code.
#
# Application code arrives the same way it would in production: as the promoted
# tarball, installed by scripts/deploy.sh. That is what lets the local rig prove
# something real. The container cannot cheat, because it starts out with nothing
# to run.

# Pinned by digest, not by tag. `python:3.12-slim` is mutable and will silently
# become a different image; this digest cannot.
FROM python:3.14-slim@sha256:d3400aa122fa42cf0af0dbe8ec3091b047eac5c8f7e3539f7135e86d855dc015

# Dependencies are baked into the environment, not the artifact -- exactly as
# they would be on a real host, and it keeps the promoted artifact small.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Run as a non-root user. A deploy target that runs everything as root is one
# container escape away from being someone else's compute.
RUN useradd --create-home --uid 10001 app \
    && mkdir -p /opt/app \
    && chown -R app:app /opt/app
USER app

WORKDIR /opt/app
ENV PYTHONPATH=/opt/app/current \
    PYTHONUNBUFFERED=1 \
    APP_ROOT=/opt/app/current \
    ARTIFACT_PATH=/opt/app/artifact.tar.gz

COPY --chown=app:app docker/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
