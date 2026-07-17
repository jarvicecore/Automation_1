# ADR 0006: Scanners are `continue-on-error`, but their findings still block

## Status

Accepted

## Context

Security scanners depend on things this repository doesn't control:
CodeQL's query packs, Snyk's and SonarQube's hosted services, network
access to fetch either. Any of those can have an outage. Two bad options
present themselves under the obvious design: either a scanner outage
blocks every PR in the repository until the vendor recovers (availability
of a third party becomes availability of your own pipeline), or a failed
scan step is silently treated the same as a clean one (a scanner that
can't run stops being distinguishable from a scanner that ran and found
nothing).

## Decision

Scan *steps* in [`_security.yml`](../../.github/workflows/_security.yml)
(Snyk, in particular) are marked `continue-on-error: true`. But every
scanner uploads SARIF to GitHub's code-scanning regardless, and it's the
resulting **code-scanning alerts** — not the job's pass/fail status — that
the branch ruleset actually enforces.

## Consequences

- A scanner *outage* doesn't wedge merges across the repository. A
  scanner *finding* still blocks the specific PR that introduced it,
  because the alert threshold in the ruleset doesn't care whether the job
  that produced the SARIF technically "passed."
- Availability and enforcement are deliberately different systems now:
  the job's green checkmark answers "did the scan run," and the Security
  tab answers "did it find anything." Reading only the checkmark can be
  misleading — a green `Security` job with a real alert sitting in the
  Security tab is a valid, intended state, not a bug.
- This shifts trust onto the SARIF upload step itself: if *that* fails
  silently, a genuine finding could be lost without either signal
  catching it. The upload step is the one part of this chain that isn't
  `continue-on-error`.
