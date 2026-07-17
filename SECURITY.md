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
| SBOM (CycloneDX) generated on every build | `_build.yml` |
| SAST | CodeQL (`security-extended`), Snyk Code |
| SCA | Dependabot, dependency review, Snyk Open Source |
| Secret detection | GitHub secret scanning + push protection, `reposentry` in the security gate |
| Repo hygiene (missing README/LICENSE, oversized files) | `reposentry` in the security gate |
| Code quality gate | SonarQube |
| Posture grading | OpenSSF Scorecard, nightly |
| Automated PR review | GitHub Copilot code review — advisory, not a required check; see note below |
| Human approval per environment | GitHub Environments + CODEOWNERS |

## What "leveraging Copilot" actually means here

Two different things both go by "Copilot," and only one is confirmed active
on this repository:

- **Copilot code review** (confirmed, observed repeatedly): automatically
  reviews every pull request and leaves comments on real issues. It caught
  a genuine bug during this repo's own documentation work — a shell
  snippet that silently no-op'd instead of demonstrating the failure it
  claimed to. It's advisory: nothing currently blocks a merge on an
  unaddressed Copilot comment.
- **Copilot coding agent** (not confirmed): the agentic mode that can be
  assigned an issue and opens its own PR autonomously. Whether it's
  licensed and enabled on this repository hasn't been tested. Don't assume
  it's available without checking.

## Verified, not assumed

Consistent with [ADR 0004](docs/adr/0004-deterministic-reproducible-builds.md)'s
standard elsewhere in this repo — this security posture has been exercised
against a real finding, not just configured and left untested. Dependabot
flagged [GHSA-86qp-5c8j-p5mr](https://github.com/advisories/GHSA-86qp-5c8j-p5mr)
(moderate, CVSS 6.5) in a transitive dependency; the fix was verified —
resolved version checked, full test suite run, the actual server booted
and probed over real HTTP — before merging, not merged on the advisory's
word alone. See [`docs/USE_CASES.md`](docs/USE_CASES.md#responding-to-a-dependency-vulnerability)
for the full sequence.

## Things that will get a PR rejected

- Adding a build step to `_deploy.yml`. Deploys must never rebuild — that breaks
  the guarantee that Prod runs the bits QA approved.
- Using `pull_request_target`, which runs untrusted PR code with write-scoped
  secrets. If you think you need it, you need a different design.
- Referencing an action by tag or branch (`@v4`, `@main`) instead of a SHA.
- Committing a credential of any kind. Use GitHub Environment secrets, or better,
  OIDC federation — the deploy job already has `id-token: write`.
