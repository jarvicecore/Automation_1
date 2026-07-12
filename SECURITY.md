# Security

## Reporting a vulnerability

Report privately through GitHub's [private vulnerability reporting](../../security/advisories/new).
Do not open a public issue, and do not disclose details in a pull request.

We acknowledge within 2 business days and aim to have a remediation plan within 10.

## Supply-chain controls in this repository

These are enforced by the pipeline, not by convention:

| Control | Where |
| --- | --- |
| Every action pinned to a full commit SHA | all workflows; Dependabot keeps them current |
| Deny-by-default `GITHUB_TOKEN` permissions | `permissions: {}` at workflow level, opted into per job |
| Runner egress monitored | `step-security/harden-runner` on every job |
| Build provenance (SLSA) attested | `_build.yml` |
| Provenance **verified before every deploy** | `_deploy.yml` — an unattested artifact cannot reach any environment |
| Artifact digest pinned through promotion | `environments/*.yaml` |
| SAST | CodeQL (`security-extended`), Snyk Code |
| SCA | Dependabot, dependency review, Snyk Open Source |
| Secret detection | GitHub secret scanning + push protection |
| Code quality gate | SonarQube |
| Posture grading | OpenSSF Scorecard, nightly |
| Human approval per environment | GitHub Environments + CODEOWNERS |

## Things that will get a PR rejected

- Adding a build step to `_deploy.yml`. Deploys must never rebuild — that breaks
  the guarantee that Prod runs the bits QA approved.
- Using `pull_request_target`, which runs untrusted PR code with write-scoped
  secrets. If you think you need it, you need a different design.
- Referencing an action by tag or branch (`@v4`, `@main`) instead of a SHA.
- Committing a credential of any kind. Use GitHub Environment secrets, or better,
  OIDC federation — the deploy job already has `id-token: write`.
