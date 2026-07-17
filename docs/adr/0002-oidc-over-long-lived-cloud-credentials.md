# ADR 0002: Use OIDC federation instead of long-lived cloud credentials

## Status

Accepted

## Context

The conventional way to let a CI job touch cloud infrastructure is to mint a
static access key/secret pair for the cloud account and store it as a
repository or environment secret. That credential typically:

- never expires unless someone remembers to rotate it,
- is scoped as broadly as whoever created it was in a hurry to make it,
- and, once it leaks (a `run:` step that echoes env vars, a fork PR that
  exfiltrates it, a compromised action), is valid until someone notices and
  revokes it.

GitHub Actions can instead present a short-lived, workflow-scoped OIDC token
to a cloud provider, which exchanges it for temporary credentials after
verifying claims like repository, branch, and environment.

## Decision

`deploy.yml` and `release.yml`'s PyPI publish job request an OIDC token
(`permissions: id-token: write`) and exchange it for scoped access —
`aws-actions/configure-aws-credentials` assuming an IAM role for deploys,
and PyPI's trusted publishing for the package release — instead of reading
a stored access key or API token from secrets.

## Consequences

- No cloud access key or PyPI API token exists in this repository's secrets
  at all; there is nothing here to leak.
- The trust relationship is scoped narrowly on the cloud/registry side (e.g.
  "only `jarvicecore/automation_1`, only the `production` environment, only
  workflow X") rather than "anyone holding this string."
- Credentials are valid only for the life of the job run — a leaked token
  from a single run is not a standing liability.
- Requires one-time setup on the cloud/registry side (an IAM OIDC identity
  provider + role trust policy; a PyPI trusted publisher entry) instead of
  just pasting a secret into repo settings. That setup cost is paid once per
  environment, not per rotation.
