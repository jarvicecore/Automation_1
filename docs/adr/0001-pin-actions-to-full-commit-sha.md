# ADR 0001: Pin third-party GitHub Actions to a full commit SHA

## Status

Accepted

## Context

Every `uses:` reference to a third-party action is a supply-chain trust
boundary — the action's code runs inside the workflow with access to
`GITHUB_TOKEN`, secrets, and (for `pull_request_target` triggers) sometimes
write access to the repository. Referencing an action by a mutable tag
(`@v4`) or branch (`@main`) means the maintainer — or anyone who compromises
their account or npm/PyPI-equivalent publish flow — can silently change what
code runs in every consumer's pipeline the next time it's re-tagged. This is
exactly the class of attack that hit `tj-actions/changed-files` in 2025.

## Decision

Every third-party action in this repo is referenced by its full 40-character
commit SHA, with the human-readable tag kept alongside as a trailing
comment for readability:

```yaml
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
```

First-party `actions/*` and `github/*` actions are pinned the same way for
consistency, even though GitHub's own supply chain is a smaller marginal
risk than a third-party maintainer's.

## Consequences

- Updates require a new SHA, not just a version bump — handled automatically
  by Dependabot's `github-actions` ecosystem, which resolves the tag a new
  release points to and opens a PR with the updated SHA + comment.
- A pinned SHA can still point to code with a vulnerability disclosed later;
  pinning stops *silent* changes, it doesn't replace patching. Dependabot
  PRs are how patches land.
- Slightly noisier diffs than `@v4`, traded deliberately for the guarantee
  that code review of a workflow file is reviewing the code that will
  actually run.
