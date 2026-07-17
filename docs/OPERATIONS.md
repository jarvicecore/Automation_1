# Operations

Configuration reference and troubleshooting for running this pipeline
day to day. For first-time setup, see [`docs/SETUP.md`](SETUP.md).

## Configuration surface

### Repository variables

Settings → Secrets and variables → Actions → Variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CODEQL_LANGUAGES_JSON` | `["actions"]` | Languages CodeQL scans. This repo runs `["actions","python"]`. |
| `ENABLE_SNYK` | *(unset)* | `true` turns the Snyk job on. |
| `ENABLE_SONAR` | *(unset)* | `true` turns the SonarQube job on. |
| `SONAR_HOST_URL` | *(unset)* | Your SonarQube server. |
| `PROMOTION_APP_ID` | *(unset)* | GitHub App ID for promotion PRs — [`docs/SETUP.md`](SETUP.md#3-create-the-promotion-github-app). |

### Repository secrets

| Secret | Purpose |
| --- | --- |
| `SNYK_TOKEN` | Snyk API token. |
| `SONAR_TOKEN` | SonarQube token. |
| `PROMOTION_APP_PRIVATE_KEY` | The promotion App's `.pem`. Without it, promotion PRs open with no checks. |

### Per-environment configuration

Settings → Environments → *(each of dev, qa, stage, uat, prod, train)*:

| Setting | Type | Purpose |
| --- | --- | --- |
| `EXTRACT_TARGET` | variable | Where this environment's artifact gets installed. `docker://automation1-qa` drives the local rig. |
| `ENVIRONMENT_URL` | variable | Optional link shown on the GitHub deployment record. |
| `SMOKE_URL` | variable | Where `smoke-test.sh` probes. Inferred for `docker://` targets. |
| `EXTRACT_CREDENTIALS` | secret | Only if the target can't use OIDC. Prefer OIDC — see [ADR 0010](adr/0010-oidc-over-long-lived-deploy-credentials.md). |

### Environment approval gates

Applied by [`scripts/bootstrap-github.ps1`](../scripts/bootstrap-github.ps1)
(enterprise configuration; see [`docs/SETUP.md`](SETUP.md#why-solo-mode-exists-and-what-it-costs)
for what solo mode changes):

| Environment | Reviewers | Wait timer | Deploys from |
| --- | --- | --- | --- |
| dev | *none* — automatic | — | `main` |
| qa | `@qa` | — | `main` |
| stage | `@qa` + `@release-managers` | — | `main` |
| uat | `@release-managers` + `@business-owners` | — | `main` |
| prod | `@release-managers` + `@security` | **10 min** | `main` |
| train | `@release-managers` + `@training` | — | `main` |

Every gated environment sets `prevent_self_review`: whoever requested a
promotion cannot also approve it (relaxed in solo mode, where there's only
one person to do either).

### Pinned actions

Every action referenced anywhere in `.github/workflows/` is pinned to a
full commit SHA, not a tag — see
[ADR 0009](adr/0009-pin-every-action-to-a-full-commit-sha.md). Current
pins (Dependabot keeps these current; this table reflects
`.github/workflows/` as of the last documentation update, not a live
query):

| Action | Version |
| --- | --- |
| `actions/checkout` | v5.0.0 |
| `actions/setup-python` | v6.0.0 |
| `actions/setup-node` | v6.0.0 |
| `actions/upload-artifact` | v5.0.0 |
| `actions/download-artifact` | v6.0.0 |
| `actions/attest-build-provenance` | v3.0.0 |
| `actions/dependency-review-action` | v4.8.2 |
| `actions/create-github-app-token` | v2.1.4 |
| `github/codeql-action` | v3.30.5 |
| `ossf/scorecard-action` | v2.4.3 |
| `step-security/harden-runner` | v2.13.1 |
| `anchore/sbom-action` | v0.20.9 |
| `SonarSource/sonarqube-scan-action` | v6.0.0 |

The base image `python:3.12-slim` in [`docker/Dockerfile`](../docker/Dockerfile)
is pinned by digest for the same reason.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Every PR blocked, nobody can approve | Enterprise ruleset applied to a solo repo — you cannot approve your own PR | Re-run `./scripts/bootstrap-github.ps1 -Solo`. See [why solo mode exists](SETUP.md#why-solo-mode-exists-and-what-it-costs). |
| Promotion PR has **no checks at all** | Promotion GitHub App not configured | [`docs/SETUP.md`, step 3](SETUP.md#3-create-the-promotion-github-app). Until then, promotion PRs merge unverified. |
| `Dependency review is not supported on this repository` | Dependency graph disabled | Enable Dependabot alerts in repo settings. |
| PR blocked on `ci-passed` that never ran | CI hasn't reported on this repo yet | Expected on a fresh repo. That's the gate working, not a misconfiguration. |
| `$'\r': command not found` on a runner | A `.sh` file got CRLF line endings | [`.gitattributes`](../.gitattributes) prevents this. Don't remove it. |
| Deploy fails: `gh attestation verify` | Artifact wasn't built by `_build.yml`, or was altered after release | **Working as designed.** Investigate before overriding — see [ADR 0001](adr/0001-binary-promotion-over-rebuild-per-environment.md). |
| Deploy fails on digest mismatch | The release asset changed after promotion was approved | **Working as designed.** Someone replaced the artifact; treat it as a security event. |
| `/version` returns `409` | Running bytes don't match the promoted digest | **Working as designed.** The service is refusing to vouch for itself — see [the tamper-detection use case](USE_CASES.md#detecting-a-tampered-deployment). |
| Promote fails: *"nothing to promote"* | Target already runs that tag, or the source environment is empty | Not an error. The workflow refuses to open an empty PR. |
| Snyk/Sonar show as **skipped** | Flag-gated, not enabled | [`docs/SETUP.md`, step 4](SETUP.md#4-turn-on-the-commercial-scanners-optional). Skipped is not the same as passing. |
| `demo.sh`: *"environment is not running"* | The local rig isn't up | `docker compose up -d --build` |
| `yq: command not found`, or manifest checks silently skipped | Wrong `yq` on `PATH` — GitHub-hosted runners ship `mikefarah/yq`, but some images/systems have `kislyuk/yq` (a different, Python-based tool) installed under the same name | Every workflow that shells out to `yq` (`deploy.yml`, `promote.yml`, `scheduled-security.yml`) checks the `--version` banner for `mikefarah` before trusting it, and fails with a clear error if it's missing or wrong. `scripts/test.sh`'s manifest check does the same but warns and skips instead of failing the build. |
| Node 20 deprecation warnings in Action logs | Upstream actions haven't bumped their runtime yet | Cosmetic. Dependabot will pick up the fix once upstream ships it. |

## What "healthy" looks like

- `ci-passed` green on every merged PR.
- Every environment's `release_tag` in `environments/*.yaml` traceable to
  a GitHub Release with a verifiable attestation.
- The nightly drift report ([`docs/USE_CASES.md`](USE_CASES.md#monitoring-drift))
  showing environments being promoted through, not stalled indefinitely
  behind `dev`.
- Security tab with zero unaddressed `critical`/`high` alerts.
- Dependabot PRs get triaged and merged (or explicitly deferred with a
  reason), not left to accumulate — an open Dependabot PR for a real
  vulnerability is a gap in the supply-chain story the rest of this repo
  tells, not a background chore. Verify the fix actually resolves the
  alert before merging it, rather than trusting the PR title — see
  [the dependency-vulnerability use case](USE_CASES.md#responding-to-a-dependency-vulnerability)
  for the standard to hold it to.
- `docker compose up -d --build && ./scripts/demo.sh` succeeding locally —
  a useful smoke test for the pipeline's own scripts independent of GitHub.
