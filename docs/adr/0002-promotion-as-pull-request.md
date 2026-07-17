# ADR 0002: Promotion is a pull request, not a button

## Status

Accepted

## Context

Once an artifact exists (see [ADR 0001](0001-binary-promotion-over-rebuild-per-environment.md)),
something has to decide when it moves from one environment to the next.
The simplest version of that is a "Deploy to Prod" button — a
`workflow_dispatch` that pushes the artifact straight to the target. That's
fast, but it leaves a single line in the Actions run log as the entire
audit trail, has no natural place to attach reviewers per environment
without writing custom approval logic, and gives nobody a diff to look at
before approving.

## Decision

Promotion is a two-step process. [`promote.yml`](../../.github/workflows/promote.yml)
verifies the source environment's artifact digest and SLSA provenance,
then **opens a pull request** that changes exactly one file —
`environments/<env>.yaml` — to point at the verified release tag. Nothing
deploys until that PR is reviewed and merged; merging it is what triggers
[`deploy.yml`](../../.github/workflows/deploy.yml).

## Consequences

- The promotion PR is reviewable (a real diff: old tag → new tag),
  blameable (who opened it, who approved it), and revertable (a normal
  `git revert`, not a bespoke rollback path — see
  [ADR 0001](0001-binary-promotion-over-rebuild-per-environment.md)).
- CODEOWNERS enforces *different* approvers per environment for free —
  `environments/prod.yaml` can require `@security`'s sign-off while
  `environments/qa.yaml` doesn't, with no custom approval logic to
  maintain.
- It costs a round trip. Promoting to Prod is at minimum: run Promote,
  wait for the PR to open, get it reviewed, merge it. That latency is the
  point — a mechanism that's *slower on purpose* around the highest-risk
  action is often exactly the design goal, not a defect to optimize away.
- Requires GitHub Actions to actually trigger checks on the promotion PR,
  which the default `GITHUB_TOKEN` cannot do (GitHub suppresses that to
  prevent recursive triggering). Without the promotion GitHub App
  configured, promotion PRs open with zero status checks — see
  [`docs/OPERATIONS.md`](../OPERATIONS.md).
