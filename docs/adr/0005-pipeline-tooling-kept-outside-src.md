# ADR 0005: Pipeline tooling lives outside `src/`

## Status

Accepted

## Context

`tools/reposentry` is a secrets/hygiene scanner used *by* the security
gate, to check the repository itself. It has nothing to do with the
extract workload in `src/app`, but the two are easy to conflate — both are
Python packages in the same repo, and a less careful layout might have put
`reposentry` under `src/` alongside the application, or had `src/app`
import a shared utility from it.

## Decision

`tools/reposentry` is a separate, self-contained package (its own
`pyproject.toml`, its own tests, its own venv) that `src/app` never
imports, and that never sits on the path [`scripts/build.sh`](../../scripts/build.sh)
packages into `dist/*.tar.gz`.

## Consequences

- Nothing built *for* the pipeline can ever ride along *inside* the
  artifact the pipeline produces and promotes. This isn't just tidiness —
  see [ADR 0001](0001-binary-promotion-over-rebuild-per-environment.md):
  the whole guarantee is that the bytes QA approved are the bytes Prod
  runs, and an accidentally-bundled dev-only dependency would still be
  "correct" bytes, just bytes nobody meant to promote.
- `tools/reposentry`'s own tests run in [`_security.yml`](../../.github/workflows/_security.yml),
  not in [`_build.yml`](../../.github/workflows/_build.yml) — it's
  verified as pipeline infrastructure, on the same cadence as CodeQL and
  dependency review, not as part of the artifact's own test gate
  (`scripts/test.sh`).
- The convention generalizes: anything written to operate *on* this
  repository (linters, scanners, generators) belongs under `tools/`;
  anything that becomes part of what gets deployed belongs under `src/`.
  A repository that grows a second in-house tool has a place for it
  already.
