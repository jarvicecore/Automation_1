# The pipeline

## The one idea

**Build once. Promote the same bytes. Never rebuild.**

CI produces a single artifact when code merges to `main`. That artifact — the
exact tarball, identified by its SHA256 — is what travels through every
environment. Nothing downstream recompiles anything. If Prod is running
`v0.1.42`, those are bit-for-bit the same bytes that QA signed off on.

This is enforced, not merely encouraged:

- `_deploy.yml` has no build step, and adding one is a rejectable change.
- Every deploy re-checks the artifact's SHA256 against the digest the promotion
  PR was approved with.
- Every deploy verifies the artifact's **SLSA provenance** — cryptographic proof
  it was produced by `_build.yml` in this repository. A tarball someone uploaded
  to the release by hand has no attestation and cannot deploy.

## Flow

```text
  PR ──► ci.yml ──────────────► build + test + scan   (nothing published)
                                        │
                                     merge
                                        ▼
       release.yml ──► build ONCE ──► attest ──► GitHub Release ──► deploy DEV
                                                        │
                                                        │  promote.yml (manual)
                                                        ▼
                                            ┌──────────────────────┐
                                            │  PROMOTION PULL      │
                                            │  REQUEST             │
                                            │  environments/qa.yaml│
                                            └──────────┬───────────┘
                                                  merge │  (CODEOWNERS approve)
                                                        ▼
                                            deploy.yml ──► deploy QA
                                                        │
                             same shape for  STAGE ► UAT ► PROD ► TRAIN
```

Promotion path (`environments/promotion-path.yaml`):

```text
dev ──► qa ──► stage ──► uat ──► prod ──► train
```

## Environments

| Env | How it gets a release | Approval |
| --- | --- | --- |
| **dev** | Automatic, on every merge to `main` | none |
| **qa** | Promotion PR from dev | `@qa` |
| **stage** | Promotion PR from qa | `@qa` + `@release-managers` |
| **uat** | Promotion PR from stage | `@release-managers` + `@business-owners` |
| **prod** | Promotion PR from uat | `@release-managers` + `@security`, plus a 10-minute wait timer |
| **train** | Promotion PR from prod | `@release-managers` + `@training` |

> **This repo is currently in solo mode.** It lives on a personal account, which
> cannot have teams, so the approver for every gated environment is `@jarvicecore`
> and the bootstrap runs as `./scripts/bootstrap-github.ps1 -Solo`. The approval
> gate is still real and still enforced — you approve each environment explicitly
> before it deploys. The table above is the enterprise target state; the README
> details exactly what solo mode relaxes and what it keeps.

`dev` deliberately has no manifest file. It always runs the latest release, by
definition, so recording that in git would mean pushing to `main` from CI —
which would require punching a bypass hole in branch protection to buy a fact we
can already derive.

Every other environment is one YAML file in `environments/`. That file *is* the
deployment state. Git history is therefore a complete, signed audit log of what
ran where and who approved it.

## Promoting a release

1. Actions → **Promote** → Run workflow.
2. Pick the target environment and give a change reference.
3. The workflow verifies the artifact's digest and provenance, then opens a PR
   changing one file.
4. The required CODEOWNERS approve it.
5. Merging it triggers the deploy. The GitHub Environment gate may still hold the
   job for reviewer approval and (for Prod) a wait timer.

### Rolling back

Revert the promotion PR. That restores the previous `release_tag` in the
manifest, which redeploys the previous artifact. Rollback is a normal, reviewed,
one-line git operation — not a special emergency path that nobody has rehearsed.

## Security controls

### GitHub-native

- **CodeQL** (`security-extended`), including the `actions` language, which scans
  these workflows themselves for CI/CD vulnerabilities.
- **Dependency review** blocks PRs introducing vulnerable or badly-licensed deps.
- **Secret scanning + push protection** rejects the push containing a credential
  rather than alerting after it has leaked.
- **Dependabot**, including the `github-actions` ecosystem — this is what makes
  SHA-pinning sustainable, since Dependabot bumps the pins for you.
- **OpenSSF Scorecard**, nightly.

### Commercial (flag-gated)

Off until you supply licences, so the pipeline is green from day one:

| | Enable with | Needs |
| --- | --- | --- |
| Snyk (SCA + Code) | `vars.ENABLE_SNYK=true` | `secrets.SNYK_TOKEN` |
| SonarQube | `vars.ENABLE_SONAR=true` | `secrets.SONAR_TOKEN`, `vars.SONAR_HOST_URL` |

Every scanner uploads SARIF, so all findings land in one Security tab and are
enforced by one ruleset.

### Platform hardening

Applied by `scripts/bootstrap-github.ps1`:

- Default `GITHUB_TOKEN` is **read-only**; jobs opt in to more, visibly, in review.
- Workflows cannot approve pull requests.
- Actions restricted to an **allow-list**; the "verified creator" badge is *not*
  blanket-trusted.
- Every action pinned to a full **commit SHA** (a tag is mutable; a SHA is not).
- Ruleset on `main`: PR required, 2 approvals, code-owner review, required status
  checks, signed commits, linear history, no force-push, no deletion — and it
  applies to admins.
- `prevent_self_review` on every gated environment: the person who requested a
  promotion cannot also approve it.
- Deployments only from `main`.
- `step-security/harden-runner` on every job, monitoring egress.

## Setup

```powershell
# Solo (this repo today): you are the only approver.
./scripts/bootstrap-github.ps1 -Solo -DryRun
./scripts/bootstrap-github.ps1 -Solo

# Enterprise: first edit the team names at the top of the script to match your org.
./scripts/bootstrap-github.ps1 -DryRun
./scripts/bootstrap-github.ps1
```

Then complete the manual steps it prints — notably the **GitHub App for promotion
PRs**. Without it, promotion PRs open with **zero status checks and can be merged
unverified**, because GitHub deliberately does not trigger workflows from PRs
created with the default `GITHUB_TOKEN`. This is the one gap that undermines the
whole model, so close it: set `vars.PROMOTION_APP_ID` and
`secrets.PROMOTION_APP_PRIVATE_KEY`.

The ruleset already requires the `ci-passed` status check. Until CI has run once,
PRs will correctly sit blocked waiting for it — that is the gate working, not a
misconfiguration.

## The seams you own

Four scripts, all stubs that run end-to-end today:

| File | Runs | Replace with |
| --- | --- | --- |
| `scripts/build.sh` | CI + release | Your real build. **Must stay deterministic** — see below. |
| `scripts/test.sh` | CI + release | Your real test suite. Non-zero exit blocks the merge. |
| `scripts/deploy.sh` | Every environment | Push extracts to that environment's target. |
| `scripts/smoke-test.sh` | After every deploy | Prove the deploy actually came up. |

`build.sh` must be **reproducible**: same commit in, same bytes out. It already
uses a fixed-mtime sorted tar and takes its build timestamp from the commit
rather than the wall clock. If you make the build non-deterministic, the digest
in a promotion manifest stops being verifiable, and the entire chain of custody
becomes decorative. Resist it.

`deploy.sh` runs unchanged for all six environments; everything that differs
arrives as GitHub Environment variables and secrets (`EXTRACT_TARGET`,
`EXTRACT_CREDENTIALS`). Do not add `if [ "$TARGET_ENV" = "prod" ]` branches — the
value of this design is that Prod's deploy path has already been rehearsed five
times before it runs.

Better still: the deploy job already has `id-token: write`, so federate into your
target platform with OIDC and delete `EXTRACT_CREDENTIALS` entirely.
