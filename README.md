# Automation_1

Enterprise CI/CD on GitHub Actions, built on one rule:

> **Build once. Promote the same bytes. Never rebuild.**

CI produces a single artifact when code merges to `main`. That exact artifact —
identified by its SHA256 — travels through every environment. If Prod is running
`v0.1.42`, those are bit-for-bit the same bytes QA signed off on.

```text
dev ──► qa ──► stage ──► uat ──► prod ──► train
 │       └───────────────────────────────────┘
 │                    promotion PRs
 └── automatic on merge to main
```

Full design notes: [docs/PIPELINE.md](docs/PIPELINE.md).

---

## Where things stand right now

Read this before you start — some of it is already done.

| | Status |
| --- | --- |
| Workflows, scripts, manifests | Committed on branch `platform/github-actions-enterprise`, open as **PR #1** |
| CI passing on that PR | ✅ green (build, CodeQL, dependency review, security gate) |
| Dependabot alerts + dependency graph | ✅ already enabled (CI fails without it) |
| Secret scanning + push protection | ✅ already on |
| GitHub teams for CODEOWNERS | ❌ **not created — this will block every PR** |
| `bootstrap-github.ps1` | ❌ not run yet |
| Promotion GitHub App | ❌ not created |
| Snyk / SonarQube | ❌ off (flag-gated, pipeline is green without them) |
| `build.sh` / `test.sh` / `deploy.sh` / `smoke-test.sh` | ⚠️ working stubs — they run, but don't do anything real |

---

## Setup, in order

The order matters. Doing step 3 before step 1 will lock you out of your own repo.

### 1. Create the teams (do this first)

[.github/CODEOWNERS](.github/CODEOWNERS) requires review from six teams. **If they
don't exist when you enable the ruleset, every pull request — including promotion
PRs — becomes unmergeable, because GitHub cannot resolve the required reviewer.**

Either create them in your org:

```
platform-engineering
security
qa
release-managers
business-owners
training
```

…or, if you're testing solo and don't want six teams yet, edit
[.github/CODEOWNERS](.github/CODEOWNERS) and the `$Teams` block at the top of
[scripts/bootstrap-github.ps1](scripts/bootstrap-github.ps1) to point at your own
username instead:

```
*   @bryan-yourhandle
```

The bootstrap script warns (rather than crashes) on a team it can't find, but the
environment gate for that team is then left **wide open** — so don't ignore the
warnings.

### 2. Merge PR #1

```powershell
gh pr merge 1 --squash
```

Do this *before* enabling the ruleset, otherwise you'll need an approval you can't
give yourself.

### 3. Run the bootstrap

This applies everything that makes the pipeline non-optional: the branch ruleset,
the six environments and their reviewer gates, the read-only default token, and
the actions allow-list.

```powershell
# Preview — changes nothing.
./scripts/bootstrap-github.ps1 -DryRun

# Apply.
./scripts/bootstrap-github.ps1
```

It's idempotent; re-run it any time you change team names.

Some calls will warn rather than fail if your plan doesn't include the feature
(GitHub Advanced Security, rulesets on private repos). That's expected.

### 4. Create the promotion GitHub App

**Do not skip this.** GitHub deliberately does not trigger workflows on PRs opened
with the default `GITHUB_TOKEN`. Without an App token, promotion PRs open with
**zero status checks and can be merged completely unverified** — which hollows out
the entire model.

1. Create a GitHub App in your org with permissions:
   - Contents: **Read and write**
   - Pull requests: **Read and write**
2. Install it on this repository.
3. Generate a private key.
4. Add to repo settings (Settings → Secrets and variables → Actions):
   - Variable `PROMOTION_APP_ID` = the App's ID
   - Secret `PROMOTION_APP_PRIVATE_KEY` = the full `.pem` contents

### 5. Configure the scanners (optional, but do it eventually)

Snyk and SonarQube are wired but skipped until you switch them on. A *skipped*
scanner catches nothing.

Repository variables / secrets:

| Setting | Type | Value |
| --- | --- | --- |
| `ENABLE_SNYK` | variable | `true` |
| `SNYK_TOKEN` | secret | your Snyk API token |
| `ENABLE_SONAR` | variable | `true` |
| `SONAR_HOST_URL` | variable | `https://sonarqube.your-corp.example` |
| `SONAR_TOKEN` | secret | your Sonar token |
| `CODEQL_LANGUAGES_JSON` | variable | e.g. `["actions","python"]` — match your stack |

`CODEQL_LANGUAGES_JSON` defaults to `["actions"]`, which scans the workflows
themselves. Add your application language once there's code to scan.

Also update `sonar.projectKey` in [sonar-project.properties](sonar-project.properties).

### 6. Configure each environment

Settings → Environments → *(each of dev, qa, stage, uat, prod, train)*:

| Setting | Type | Purpose |
| --- | --- | --- |
| `EXTRACT_TARGET` | variable | Where this environment's extracts land |
| `ENVIRONMENT_URL` | variable | Optional link shown on the deployment |
| `EXTRACT_CREDENTIALS` | secret | Only if you can't use OIDC |

The deploy job already has `id-token: write`. **Prefer OIDC federation and delete
`EXTRACT_CREDENTIALS` entirely** — a long-lived secret in six environments is six
places to leak it from.

### 7. Replace the stubs

Four scripts. They run end-to-end today so you can test the *pipeline* before you
have an *application*, but they don't do anything real.

| File | Runs | Replace with |
| --- | --- | --- |
| [scripts/build.sh](scripts/build.sh) | CI + release | Your build. **Must stay deterministic** — see below. |
| [scripts/test.sh](scripts/test.sh) | CI + release | Your tests. Non-zero exit blocks the merge. |
| [scripts/deploy.sh](scripts/deploy.sh) | Every environment | Push extracts to `$EXTRACT_TARGET`. |
| [scripts/smoke-test.sh](scripts/smoke-test.sh) | After every deploy | Prove the deploy came up. |

Two rules that are load-bearing, not stylistic:

- **`build.sh` must be reproducible** — same commit in, same bytes out. It already
  uses a fixed-mtime sorted tar and takes its timestamp from the commit rather
  than the wall clock. If you make it non-deterministic, the digest recorded in a
  promotion manifest stops being verifiable and the whole chain of custody becomes
  decorative.
- **`deploy.sh` must not branch on environment.** No `if [ "$TARGET_ENV" = "prod" ]`.
  The value of this design is that by the time a deploy runs in Prod, the identical
  code path has already been rehearsed five times.

---

## Daily use

### Shipping a change

Open a PR. CI builds, tests and scans it. Merge it. That mints a release
(`v0.1.<run>`), attests its provenance, and auto-deploys **dev**. Nothing else
moves without a human.

### Promoting

1. **Actions → Promote → Run workflow**
2. Pick the target environment and enter a change/ticket reference.
3. The workflow verifies the artifact's digest and build provenance, then opens a
   PR changing one line in `environments/<env>.yaml`.
4. The CODEOWNERS for that environment approve it.
5. Merging it deploys. The GitHub Environment gate may still hold the job for
   reviewer approval, and Prod has a 10-minute wait timer.

You can only promote along the path in
[environments/promotion-path.yaml](environments/promotion-path.yaml). You cannot
skip QA to reach Prod.

### Rolling back

Revert the promotion PR. That restores the previous `release_tag`, which redeploys
the previous artifact.

Rollback is a normal, reviewed, one-line git operation — not a special emergency
path nobody has rehearsed.

### Checking what's where

`environments/*.yaml` **is** the deployment state. Git history is the audit log of
what ran where and who approved it.

`dev` has no manifest on purpose: it always runs the latest release, so recording
that in git would mean pushing to `main` from CI, which would require a bypass hole
in the branch ruleset — a real weakening, to buy a fact we can already derive.

The nightly [Scheduled Security](.github/workflows/scheduled-security.yml) run also
prints a drift table showing how far Prod trails Dev.

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Dependency review is not supported on this repository` | Dependency graph disabled | Enable Dependabot alerts. *(Already done — but this is what bit us first.)* |
| Every PR blocked, no one can approve | CODEOWNERS names a team that doesn't exist | Create the teams, or point CODEOWNERS at real handles. **Step 1.** |
| Promotion PR has **no checks at all** | Promotion GitHub App not configured | **Step 4.** Until then, promotion PRs merge unverified. |
| PR blocked on `ci-passed` that never ran | CI hasn't reported on this repo yet | Expected on a fresh repo. That's the gate working. |
| `$'\r': command not found` on a runner | A `.sh` file got CRLF endings | [.gitattributes](.gitattributes) prevents this. Don't remove it. |
| Deploy fails: `gh attestation verify` | Artifact wasn't built by `_build.yml`, or was altered after release | **Working as designed.** Investigate before overriding. |
| Deploy fails on digest mismatch | The release asset changed after promotion was approved | **Working as designed.** Someone replaced the artifact. |
| Snyk/Sonar show as *skipped* | Flag-gated, not enabled | **Step 5.** Skipped ≠ passing. |
| Node 20 deprecation warnings | Upstream actions haven't bumped yet | Cosmetic. Dependabot will pick it up. |

---

## Security posture

Everything below is enforced by the platform, not by convention.

**GitHub-native:** CodeQL (`security-extended`, including the `actions` language —
it scans these workflows for CI/CD vulnerabilities), dependency review, secret
scanning with push protection, Dependabot (including the `github-actions`
ecosystem), OpenSSF Scorecard nightly.

**Commercial:** Snyk (SCA + SAST) and SonarQube, flag-gated. All scanners emit
SARIF into a single Security tab, enforced by a single ruleset.

**Supply chain:** every artifact carries SLSA build provenance, and
[_deploy.yml](.github/workflows/_deploy.yml) **verifies it before every single
deploy**. An artifact someone uploaded to a release by hand has no attestation and
cannot reach any environment. Every deploy also re-checks the SHA256 against the
digest the promotion PR was approved with.

**Platform:** read-only default `GITHUB_TOKEN`; actions restricted to an allow-list
(the "verified creator" badge is *not* blanket-trusted); every action pinned to a
full commit SHA; signed commits; linear history; 2 approvals plus code-owner
review; `prevent_self_review`, so whoever requested a promotion cannot also approve
it; deployments only from `main`.

Report vulnerabilities via [SECURITY.md](SECURITY.md).
