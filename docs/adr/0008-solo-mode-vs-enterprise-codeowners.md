# ADR 0008: A separate "solo mode" ruleset, rather than relaxing the enterprise one

## Status

Accepted

## Context

The enterprise-target branch ruleset requires 2 approving reviews,
code-owner review, and signed commits, and every gated environment sets
`prevent_self_review`. Those controls assume more than one human exists.
This repository currently lives on a personal GitHub account —
`jarvicecore` — which cannot have teams, and GitHub will not let an
account approve its own pull request under any configuration. Applying
the enterprise ruleset as-is to a single-operator repo doesn't make it
stricter; it makes every PR, including every promotion PR, permanently
unmergeable. A team that inherits a repo in this state usually discovers
it the first time they try to merge anything.

## Decision

[`scripts/bootstrap-github.ps1`](../../scripts/bootstrap-github.ps1)
applies one of two committed ruleset files based on a `-Solo` flag:
[`rulesets/main.json`](../../.github/rulesets/main.json) (enterprise) or
[`rulesets/main-solo.json`](../../.github/rulesets/main-solo.json) (solo).
Solo mode relaxes exactly four controls — required approving reviews (2 →
0), code-owner review (required → not required), `prevent_self_review`
(on → off), and signed commits (required → not required) — and leaves
every other control identical: PR required to reach `main`, `ci-passed`
required, linear history, squash-only, no force-push, no deletion, and
**every gated environment past dev still requires an explicit approval
click before it deploys.**

## Consequences

- The four relaxed controls are exactly the ones that specifically assume
  a second reviewer exists; nothing else moves. `-Solo` isn't "the
  ruleset with fewer checks," it's "the same ruleset with the checks that
  can't be satisfied by one person removed."
- The relaxation is explicit and visible — a named flag, a second
  committed ruleset file, a table in the README of exactly what changes —
  rather than an operator quietly disabling individual protections by
  hand until the ruleset stops deadlocking. The second path leaves no
  record of what was weakened or why.
- Running the bootstrap **without** `-Solo` on a personal account is
  detected and fails loudly rather than silently applying a ruleset that
  would deadlock every PR.
- Moving to an org later is a two-file change, not a redesign: swap the
  commented enterprise block into [`CODEOWNERS`](../../.github/CODEOWNERS),
  re-run the bootstrap without `-Solo`, done.
