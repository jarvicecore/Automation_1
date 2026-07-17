# ADR 0003: `dev` has no manifest file

## Status

Accepted

## Context

Every other environment's state lives in `environments/<env>.yaml` —
which release tag it runs, who promoted it, when. `dev` is different: it
receives every release automatically, the moment [`release.yml`](../../.github/workflows/release.yml)
publishes it. The obvious-looking choice is to give `dev` a manifest too,
for consistency with the other five environments, and have `release.yml`
write to it after each deploy.

## Decision

`dev` has **no manifest file**. [`environments/promotion-path.yaml`](../../environments/promotion-path.yaml)
documents that promoting "from dev" means resolving the latest GitHub
Release directly (`gh release list --limit 1`), not reading a file.

## Consequences

- Writing `environments/dev.yaml` after every release would mean CI
  pushing to `main` — which requires a bypass hole in the branch ruleset
  for the workflow identity. That's a real weakening of branch protection,
  bought only to record a fact the system can already derive: dev is
  whatever the latest release is, by definition.
- `deploy.yml`'s manifest-change detector explicitly skips
  `environments/dev.yaml` and `environments/promotion-path.yaml` in its
  diff loop — a reader who doesn't know this decision will reasonably
  wonder why. The header comment in `deploy.yml` and this ADR are the
  answer.
- One asymmetry to hold in your head: five environments are "whatever the
  file says," one is "whatever's newest." Both are correct; they're
  answering different questions given each environment's actual role.
