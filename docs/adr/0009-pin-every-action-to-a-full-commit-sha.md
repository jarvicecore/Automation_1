# ADR 0009: Every third-party Action is pinned to a full commit SHA

## Status

Accepted

## Context

A `uses:` reference to a GitHub Action is a trust boundary — the
referenced code runs inside the job with access to `GITHUB_TOKEN` and
whatever secrets that job's `permissions:` and environment expose.
Referencing an action by a mutable tag (`@v4`) or branch (`@main`) means
the action's maintainer — or anyone who compromises their account or
publish flow — can change what code runs the next time that tag is
re-pointed, with no corresponding change in this repository's history.
This is the exact class of attack that hit `tj-actions/changed-files` in
2025: a widely-used, seemingly reputable action, re-tagged to run
credential-exfiltrating code in every consumer that trusted the tag.

## Decision

Every `uses:` line in every workflow — first-party (`actions/*`,
`github/*`) and third-party alike — is pinned to a full 40-character
commit SHA, with the human-readable version kept as a trailing comment:

```yaml
uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
```

`scripts/bootstrap-github.ps1` additionally applies an actions
**allow-list** at the repository level, so a workflow can't casually add
a new unpinned or unreviewed action even if someone tries.

## Consequences

- Reviewing a workflow-file diff is reviewing the code that will actually
  run — a SHA can't be silently repointed the way a tag can. A malicious
  or compromised update to a dependency shows up as a visible diff to a
  new SHA, not as a no-op.
- Updates now require a new SHA rather than a version-range bump, which
  would be unsustainable by hand across a dozen actions. Dependabot's
  `github-actions` ecosystem (configured in
  [`.github/dependabot.yml`](../../.github/dependabot.yml)) closes that
  gap: it resolves the SHA a new tag points to and opens a PR bumping it,
  so pinning costs nothing in ongoing maintenance.
- A pinned SHA can still point to code with a vulnerability disclosed
  later — pinning stops *silent* changes, it doesn't substitute for
  patching. The Dependabot PRs it generates are how patches actually
  land; pinning and automated updates are a pair, not alternatives.
