# ADR 0007: Deploys queue behind each other; they don't cancel

## Status

Accepted

## Context

GitHub Actions' `concurrency` group is a natural fit for stopping two
deploys to the same environment from racing — but it defaults to
`cancel-in-progress: true` in most examples (including this repo's own
[`ci.yml`](../../.github/workflows/ci.yml), where cancelling a superseded
PR's build is exactly right: nobody cares about the output of a build for
code that no longer exists). Applying that same default to deploys means
a second promotion triggered mid-deploy would kill the first one wherever
it happened to be.

## Decision

[`_deploy.yml`](../../.github/workflows/_deploy.yml)'s concurrency group
sets `cancel-in-progress: false`. A deploy to a given environment always
runs to completion before the next queued one starts.

## Consequences

- A half-finished production deploy — artifact partially unpacked,
  service mid-restart — is a worse state to be interrupted into than the
  minute or two it costs to let it finish and let the next one queue
  behind it.
- This is the opposite tradeoff from `ci.yml`'s concurrency policy on
  purpose. The two are governed by different risk profiles (throwaway
  build output vs. live environment state), and applying one blanket
  concurrency policy across the whole repository would have gotten one of
  them wrong.
- The cost is queueing latency under heavy promotion traffic — multiple
  promotions to the same environment in quick succession serialize rather
  than overlap. For the cadence this pipeline is designed around
  (deliberate, reviewed promotions, not high-frequency automated ones),
  that's the right side to be slow on.
