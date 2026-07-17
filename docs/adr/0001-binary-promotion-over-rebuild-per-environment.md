# ADR 0001: Binary promotion over rebuild-per-environment

## Status

Accepted

## Context

The conventional pattern for multi-environment CI/CD is to rebuild the
artifact at every stage: dev builds from `main`, then QA checks out the same
commit and builds again, then Prod does the same. Each rebuild is a chance
for the artifact to differ — a dependency resolved to a newer patch version,
a slightly different build image, a flaky step that behaves differently
under load. When that happens, "QA passed" stops being evidence about what
Prod is about to run. Nobody notices until an incident, and even then the
gap is hard to prove because there was never a single artifact whose journey
could be traced.

## Decision

CI builds a deployable artifact **exactly once**, in [`_build.yml`](../../.github/workflows/_build.yml),
triggered only by a merge to `main`. That artifact's SHA256 digest is
recorded the moment it's built and never recomputed from source again.
Every environment after `dev` receives that same tarball, downloaded from
the GitHub Release and re-verified against the recorded digest —
[`_deploy.yml`](../../.github/workflows/_deploy.yml) has no build step, and
adding one is treated as a rejectable change (see
[`SECURITY.md`](../../SECURITY.md)).

## Consequences

- "QA approved this" and "Prod is running this" refer to the literal same
  bytes, not two builds of the same source that are assumed to be
  equivalent. The gap between assumption and bytes-on-disk is closed.
- Rollback becomes a data operation, not a rebuild: revert the promotion PR
  and the previous artifact redeploys unchanged (see
  [ADR 0002](0002-promotion-as-pull-request.md)).
- The build step (`scripts/build.sh`) carries a heavier responsibility as a
  result — it must be deterministic, or the digest recorded at build time
  stops meaning anything (see
  [ADR 0004](0004-deterministic-reproducible-builds.md)).
- This only works because the artifact is a single self-contained tarball.
  A workload that legitimately needs environment-specific compilation (not
  just environment-specific *configuration*) doesn't fit this model without
  rethinking what "the artifact" is.
