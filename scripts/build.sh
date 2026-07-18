#!/usr/bin/env bash
#
# Build hook. Produces exactly one tarball in dist/.
#
# This is a working stub so the pipeline runs end-to-end today. Replace the
# packaging section with your real build (compile, bundle extract definitions,
# vendor dependencies, whatever "the binary" means for your data extracts).
#
# Contract with the pipeline -- do not break these:
#   * Must emit exactly one dist/*.tar.gz
#   * Must be deterministic: same commit in, same bytes out. The whole promotion
#     model rests on the artifact being reproducible and identifiable.
#   * Must not reach out to the network for anything that could change between
#     runs (pin every dependency).

set -euo pipefail

VERSION="${BUILD_VERSION:?BUILD_VERSION must be set}"
SHA="${BUILD_SHA:-local}"
NAME="secure-release-pipeline"

echo "==> Building ${NAME} ${VERSION} (${SHA})"

rm -rf dist build
mkdir -p dist build/"${NAME}"

# ---------------------------------------------------------------------------
# TODO: your real build goes here.
#
# For a data-extract workload this typically means staging the things the
# runtime needs: extract definitions, SQL, transformation scripts, schema
# contracts, and a manifest describing them.
# ---------------------------------------------------------------------------
if [ -d src ]; then
  cp -R src/. "build/${NAME}/"
else
  echo "    (no src/ directory yet -- packaging a placeholder)"
  mkdir -p "build/${NAME}/extracts"
fi

# built_at comes from the COMMIT time, never from `date`. Using the wall clock
# here would mean two builds of the same commit produce different bytes, and the
# digest recorded in a promotion manifest would no longer be reproducible --
# which quietly destroys the ability to prove what is running in prod.
if built_at="$(git log -1 --format=%cI 2>/dev/null)" && [ -n "$built_at" ]; then
  :
else
  built_at='1970-01-01T00:00:00Z'
fi

cat > "build/${NAME}/BUILDINFO" <<EOF
name=${NAME}
version=${VERSION}
commit=${SHA}
built_at=${built_at}
EOF

# Deterministic tar: fixed mtime, sorted entries, no owner metadata. Without
# this the digest changes on every build and "promote this exact digest"
# becomes meaningless.
#
# gzip itself is not exempt: tar's built-in -z pipes through a gzip that embeds
# its own header timestamp (and, depending on version, the source filename),
# which would make the compressed bytes differ between builds even though the
# uncompressed tar is identical. Piping through `gzip -n` explicitly suppresses
# that header metadata so the final .tar.gz is bit-for-bit reproducible too.
tar \
  --sort=name \
  --mtime='UTC 2020-01-01' \
  --owner=0 --group=0 --numeric-owner \
  --format=gnu \
  -cf - \
  -C build "${NAME}" \
  | gzip -n > "dist/${NAME}-${VERSION}.tar.gz"

echo "==> Wrote dist/${NAME}-${VERSION}.tar.gz"
