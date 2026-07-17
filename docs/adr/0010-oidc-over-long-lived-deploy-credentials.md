# ADR 0010: OIDC federation over long-lived deploy credentials

## Status

Accepted (mechanism enabled; not yet wired to a specific external platform
— see [Consequences](#consequences))

## Context

The conventional way for a CI job to reach a deployment target — a cloud
account, an orchestrator's API — is a long-lived credential stored as a
GitHub Environment secret (`EXTRACT_CREDENTIALS` in this repo's
configuration surface). That credential typically never expires unless
someone remembers to rotate it, is scoped as broadly as whoever created it
had time for, and if it leaks — a misconfigured `run:` step, a compromised
action upstream — is valid until someone notices and revokes it, across
however many of the six environments it was reused for.

GitHub Actions can instead present a short-lived, workflow-scoped OIDC
token that the target platform exchanges for temporary credentials after
verifying claims like repository, ref, and environment.

## Decision

[`_deploy.yml`](../../.github/workflows/_deploy.yml) grants every deploy
job `id-token: write`, and `scripts/deploy.sh`'s documentation explicitly
prefers OIDC federation over `EXTRACT_CREDENTIALS`, which exists only as
a fallback for targets that can't support it.

## Consequences

- Where OIDC is wired up, no static credential exists in this repository's
  secrets to leak, and the trust relationship is scoped narrowly on the
  target platform's side (this repo, this environment, this workflow) —
  not "anyone holding this string."
- This is the honest state today: the mechanism is enabled
  (`id-token: write` is granted, and the local Docker rig's `deploy.sh`
  path needs no credential at all) but not yet exercised against a real
  cloud target, because `deploy.sh`'s non-Docker branch is still a
  documented stub (see [`docs/SETUP.md`](../SETUP.md), step 6). Wiring a
  real target means configuring the identity provider trust policy on
  that platform's side and replacing the stub — the workflow-side grant
  doesn't need to change.
- `EXTRACT_CREDENTIALS` staying in the configuration surface as a fallback
  is deliberate, not an oversight: some targets genuinely can't do OIDC.
  It's documented as the exception path, not the default, so a future
  reader reaches for it only when OIDC has actually been ruled out.
