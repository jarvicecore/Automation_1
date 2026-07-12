# Automation_1

Enterprise CI/CD on GitHub Actions for a data-extract workload, built on one rule:

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

## Contents

- [See it work, in two minutes](#see-it-work-in-two-minutes)
- [Where things stand right now](#where-things-stand-right-now)
- [How it works](#how-it-works)
- [Setup, in order](#setup-in-order)
- [Daily use](#daily-use)
- [Reference](#reference)
  - [Repository layout](#repository-layout)
  - [Workflows](#workflows)
  - [Configuration surface](#configuration-surface)
  - [The reference app](#the-reference-app)
  - [The Docker rig](#the-docker-rig)
  - [Scripts](#scripts)
- [Security posture](#security-posture)
- [Design decisions](#design-decisions-and-why)
- [Troubleshooting](#troubleshooting)

---

## See it work, in two minutes

The repo ships a **six-environment rig** in Docker. Each container is a *deployment
target*, not an application — they come up **empty** and idle until an artifact is
installed into them, exactly like a freshly provisioned host. That's what makes this
a fair test rather than a demo that flatters itself.

```bash
docker compose up -d --build   # six empty environments: dev qa stage uat prod train
./scripts/demo.sh              # build ONE artifact, promote it through all six
```

```text
SIX ENVIRONMENTS, ONE DIGEST
ENV     PORT    VERIFIED  DIGEST RUNNING
dev     8081    yes       0c0e8fbe4428fd223c0af5df0f914abf...
qa      8082    yes       0c0e8fbe4428fd223c0af5df0f914abf...
stage   8083    yes       0c0e8fbe4428fd223c0af5df0f914abf...
uat     8084    yes       0c0e8fbe4428fd223c0af5df0f914abf...
prod    8085    yes       0c0e8fbe4428fd223c0af5df0f914abf...
train   8086    yes       0c0e8fbe4428fd223c0af5df0f914abf...

All six environments are running the identical artifact.
```

Open <http://localhost:8085>. It says **Hello, World** — and then proves which build
of itself is saying it. The service re-hashes the tarball it was unpacked from and
compares that against the digest the promotion recorded. `/version` returns **409**
if they disagree, so a service that cannot prove its own identity **fails its own
deployment** rather than quietly serving traffic.

### Try to break it

A check that can't fail is decoration. Prove this one can:

```bash
docker exec -u root automation1-prod sh -c 'echo tampered >> /opt/app/artifact.tar.gz'
docker restart automation1-prod && sleep 5

ARTIFACT_SHA256=<the digest demo.sh printed> \
EXTRACT_TARGET=docker://automation1-prod \
  ./scripts/smoke-test.sh prod        # exits 1 — deployment blocked
```

`/version` flips to `409 self_verified:false`, and the smoke test fails the deploy.
Re-run `./scripts/demo.sh` to restore it. Tear down with `docker compose down -v`.

**What this does and doesn't prove.** The local rig proves the *data path*: build
once, install the same bytes six times, detect tampering. The *control plane* —
approval gates, CODEOWNERS, SLSA attestation, promotion PRs — runs on GitHub and is
exercised by the real workflows. The two halves meet in `deploy.sh`, which is the
same script in both.

---

## Where things stand right now

Read this before you start — some of it is already done.

| | Status |
| --- | --- |
| Workflows, scripts, manifests, app | Committed on branch `platform/github-actions-enterprise`, open as **PR #1** |
| CI on that PR | ✅ green — build, 11 tests, CodeQL (`actions` + `python`), dependency review, security gate |
| Dependabot alerts + dependency graph | ✅ already enabled (dependency review fails without it) |
| Secret scanning + push protection | ✅ already on |
| `CODEQL_LANGUAGES_JSON` | ✅ set to `["actions","python"]` |
| Reference app + six-environment Docker rig | ✅ real and working — `./scripts/demo.sh` |
| `build.sh` / `test.sh` / `smoke-test.sh` | ✅ real (deterministic packaging, pytest, provenance + contract checks) |
| **GitHub teams for CODEOWNERS** | ❌ **not created — this will block every PR** |
| `bootstrap-github.ps1` | ❌ not run yet |
| Promotion GitHub App | ❌ not created — promotion PRs get **no checks** until it is |
| Snyk / SonarQube | ❌ off (flag-gated; pipeline is green without them) |
| `deploy.sh` | ⚠️ real for the Docker rig; **stub for your real target** — see [step 7](#7-point-deploysh-at-your-real-target) |

---

## How it works

### Build once

A merge to `main` runs [release.yml](.github/workflows/release.yml), which is the
**only** workflow permitted to build a deployable artifact. It produces
`automation1-<version>.tar.gz`, records its SHA256, generates a CycloneDX SBOM,
attaches **SLSA build provenance**, and publishes all of it to a GitHub Release
(`v0.1.<run_number>`). It then auto-deploys **dev**.

Nothing downstream ever rebuilds. [_deploy.yml](.github/workflows/_deploy.yml) has
no build step, and adding one is a rejectable change.

### Promote by pull request

Every environment past dev is a YAML file in [environments/](environments/)
recording which release tag it runs. **That file is the deployment state.**

Running the **Promote** workflow:

1. Resolves the source environment from
   [promotion-path.yaml](environments/promotion-path.yaml).
2. Downloads the release asset and **re-hashes it**, confirming it still matches the
   digest the upstream environment approved.
3. **Verifies its SLSA provenance** back to `_build.yml` in this repo.
4. Only then opens a PR changing one line in `environments/<env>.yaml`.

The PR is the approval artifact — reviewable, blameable, revertable. CODEOWNERS
decides who can approve it per environment. Merging it triggers
[deploy.yml](.github/workflows/deploy.yml).

### Verify at the door

Before *any* environment receives bits, `_deploy.yml` independently re-checks both
the digest and the provenance. A tarball someone hand-uploaded to a release has no
attestation and dies here. Then the deployed service performs a **third** check on
itself at startup (see [the reference app](#the-reference-app)).

Three independent checks, at promote time, at deploy time, and at run time.

### Roll back

Revert the promotion PR. That restores the previous `release_tag`, which redeploys
the previous artifact. Rollback is a normal, reviewed, one-line git operation — not
a special emergency path nobody has rehearsed.

---

## Setup, in order

**The order matters. Doing step 3 before step 1 will lock you out of your own repo.**

### 1. Create the teams (do this first)

[.github/CODEOWNERS](.github/CODEOWNERS) requires review from six teams. **If they
don't exist when you enable the ruleset, every pull request — including promotion
PRs — becomes unmergeable, because GitHub cannot resolve the required reviewer.**

Either create them in your org:

```text
platform-engineering    qa                  business-owners
security                release-managers    training
```

…or, if you're testing solo, edit [.github/CODEOWNERS](.github/CODEOWNERS) and the
`$Teams` block at the top of
[scripts/bootstrap-github.ps1](scripts/bootstrap-github.ps1) to point at your own
username:

```text
*   @your-handle
```

The bootstrap script *warns* rather than crashes on a team it can't find — but the
environment gate for that team is then left **wide open**. Don't ignore the warnings.

### 2. Merge PR #1

```powershell
gh pr merge 1 --squash
```

Do this *before* enabling the ruleset, or you'll need approvals you can't give
yourself.

### 3. Run the bootstrap

Applies everything that makes the pipeline non-optional: the branch ruleset, the six
environments and their reviewer gates, the read-only default token, the actions
allow-list, and the promotion labels.

```powershell
./scripts/bootstrap-github.ps1 -DryRun   # preview, changes nothing
./scripts/bootstrap-github.ps1           # apply
```

Idempotent — re-run it any time you change team names. Calls that need a feature your
plan lacks (GitHub Advanced Security, rulesets on private repos) *warn* rather than
abort.

### 4. Create the promotion GitHub App

**Do not skip this.** GitHub deliberately does not trigger workflows on PRs opened
with the default `GITHUB_TOKEN`. Without an App token, promotion PRs open with **zero
status checks and can be merged completely unverified** — which hollows out the
entire model.

1. Create a GitHub App in your org with:
   - **Contents:** Read and write
   - **Pull requests:** Read and write
2. Install it on this repository.
3. Generate a private key.
4. Settings → Secrets and variables → Actions:
   - Variable `PROMOTION_APP_ID` = the App's ID
   - Secret `PROMOTION_APP_PRIVATE_KEY` = the full `.pem` contents

### 5. Turn on the commercial scanners

Snyk and SonarQube are wired but **skipped** until you switch them on. A *skipped*
scanner catches nothing. See [configuration surface](#configuration-surface) for the
variables. Also update `sonar.projectKey` in
[sonar-project.properties](sonar-project.properties).

### 6. Configure each environment

Settings → Environments → *(dev, qa, stage, uat, prod, train)* → add `EXTRACT_TARGET`
and optionally `ENVIRONMENT_URL`.

The deploy job already has `id-token: write`. **Prefer OIDC federation and skip
`EXTRACT_CREDENTIALS` entirely** — a long-lived secret across six environments is six
places to leak it from.

### 7. Point `deploy.sh` at your real target

The reference app in [src/app/](src/app/) is a real, working service. Keep it until
your own extracts are ready — it costs nothing and keeps the gates exercised.

`deploy.sh` dispatches on `EXTRACT_TARGET`. A `docker://…` value drives the local rig;
anything else falls through to a clearly marked `TODO` where your Airflow / ADF /
Databricks / scheduler call belongs. The verification either side of it — digest
check, attestation, smoke test — already works and doesn't change.

**Two rules that are load-bearing, not stylistic:**

- **`build.sh` must stay reproducible** — same commit in, same bytes out. It uses a
  fixed-mtime sorted tar and takes its timestamp from the commit rather than the wall
  clock. Make it non-deterministic and the digest in a promotion manifest stops being
  verifiable; the whole chain of custody becomes decorative.
- **`deploy.sh` must not branch on environment.** No `if [ "$TARGET_ENV" = "prod" ]`.
  The value of this design is that by the time a deploy runs in Prod, the identical
  code path has already been rehearsed five times.

---

## Daily use

### Shipping a change

Open a PR. CI builds, tests and scans it. Merge it. That mints a release
(`v0.1.<run>`), attests its provenance, and auto-deploys **dev**. Nothing else moves
without a human.

### Promoting

1. **Actions → Promote → Run workflow**
2. Pick the target environment; enter a change/ticket reference (required — it lands
   in the PR body as the audit trail).
3. The workflow verifies digest + provenance, then opens a promotion PR.
4. That environment's CODEOWNERS approve.
5. Merging deploys. The GitHub Environment gate may *still* hold the job for reviewer
   approval, and Prod adds a 10-minute wait timer.

You can only promote along the path in
[promotion-path.yaml](environments/promotion-path.yaml). You cannot skip QA to reach
Prod. The workflow also refuses a **no-op promotion** (target already runs that tag),
so nobody burns a review on an empty PR.

### Checking what's where

`environments/*.yaml` **is** the deployment state; git history is the audit log of
what ran where and who approved it.

The nightly [Scheduled Security](.github/workflows/scheduled-security.yml) run prints
a **drift table** showing how far Prod trails Dev. A pipeline nobody promotes through
is one that will get bypassed under pressure, so the drift number is an early warning
about the process, not just the code.

---

## Reference

### Repository layout

```text
.github/
  workflows/
    ci.yml                  PR gate — build, test, scan. Publishes nothing.
    release.yml             Merge to main → build ONCE, attest, release, deploy dev.
    promote.yml             Manual → opens a promotion PR for one environment.
    deploy.yml              Merged promotion PR → deploy that environment.
    scheduled-security.yml  Nightly deep scan + Scorecard + drift report.
    _build.yml              Reusable: build, test, SBOM, provenance.
    _security.yml           Reusable: CodeQL, dep review, Snyk, Sonar, gate.
    _deploy.yml             Reusable: verify, then deploy one environment.
  rulesets/main.json        Branch protection for main, applied by the bootstrap.
  CODEOWNERS               Who approves what. The per-environment approval gate.
  dependabot.yml           github-actions + pip + docker ecosystems.
  pull_request_template.md

environments/
  promotion-path.yaml      The promotion topology. Edit to reshape the pipeline.
  qa.yaml  stage.yaml  uat.yaml  prod.yaml  train.yaml
                           Deployment state. dev has none — see design decisions.

src/app/
  main.py                  FastAPI: /, /healthz, /version, /extract
  provenance.py            Self-verification: re-hashes its own artifact.
  extract.py               The extract + its schema contract.
tests/test_app.py          11 tests, including the tamper-detection path.

scripts/
  build.sh                 Deterministic tarball → dist/
  test.sh                  pytest + pipeline self-checks
  deploy.sh                Install artifact into an environment
  smoke-test.sh            Liveness + provenance + digest + contract
  demo.sh                  Build once, promote through all six, locally
  bootstrap-github.ps1     Platform hardening via the GitHub API

docker/
  Dockerfile               The ENVIRONMENT image (runtime + deps, no app code)
  entrypoint.sh            Idles until a release is deployed into it
docker-compose.yml         Six environments, ports 8081–8086

VERSION                    Version base. Full version = <base>.<run_number>
sonar-project.properties
.gitattributes             Forces LF on .sh — prevents $'\r' failures on runners
```

### Workflows

| Workflow | Trigger | What it does |
| --- | --- | --- |
| **CI** | `pull_request` → main, `merge_group` | Build (no publish), test, CodeQL, dependency review, Snyk, Sonar. Ends in `ci-passed`. |
| **Release** | `push` → main *(ignores `environments/**`, `docs/**`, `*.md`)* | Builds **once**, attests provenance, publishes a GitHub Release, auto-deploys dev. |
| **Promote** | `workflow_dispatch` | Verifies digest + provenance, opens a promotion PR. |
| **Deploy** | `push` → main touching `environments/{qa,stage,uat,prod,train}.yaml` | Detects which manifest moved; deploys that environment. |
| **Scheduled Security** | `cron 17 3 * * *` | Full scan at `medium` severity, OpenSSF Scorecard, drift report. |

Reusable (`_`-prefixed, called by the above):

| Workflow | Purpose |
| --- | --- |
| **_build** | harden-runner → checkout → Python 3.12 → `build.sh` → `test.sh` → digest → SBOM → **attest** (release only) → upload. |
| **_security** | CodeQL matrix, dependency review, Snyk, SonarQube, plus a `gate` job that aggregates them. |
| **_deploy** | Downloads the release asset, verifies digest, verifies attestation, runs `deploy.sh` + `smoke-test.sh`. Bound to the GitHub Environment, so approval gates apply. |

**Why `ci-passed` and `gate` exist.** Required status checks are brittle when pointed
at matrixed or conditional jobs — a *skipped* job never reports, so the check hangs
forever. These aggregators always report and fail if any upstream job genuinely
failed. Point branch protection at `ci-passed` and it stays correct no matter how many
jobs you add.

**Versioning.** `VERSION` holds the base (`0.1`); the full version is
`<base>.<github.run_number>`, released as tag `v<version>`. PR builds get a
`-pr<N>` suffix and are never published.

### Configuration surface

**Repository variables** — Settings → Secrets and variables → Actions → Variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CODEQL_LANGUAGES_JSON` | `["actions"]` | Languages CodeQL scans. **Currently `["actions","python"]`.** |
| `ENABLE_SNYK` | *(unset)* | `true` turns the Snyk job on. |
| `ENABLE_SONAR` | *(unset)* | `true` turns the SonarQube job on. |
| `SONAR_HOST_URL` | *(unset)* | Your SonarQube server. |
| `PROMOTION_APP_ID` | *(unset)* | GitHub App ID for promotion PRs. **[Step 4](#4-create-the-promotion-github-app).** |

**Repository secrets:**

| Secret | Purpose |
| --- | --- |
| `SNYK_TOKEN` | Snyk API token. |
| `SONAR_TOKEN` | SonarQube token. |
| `PROMOTION_APP_PRIVATE_KEY` | The App's `.pem`. Without it, promotion PRs get no checks. |

**Per-environment** — Settings → Environments → *(each env)*:

| Setting | Type | Purpose |
| --- | --- | --- |
| `EXTRACT_TARGET` | variable | Where this environment's extracts land. `docker://automation1-qa` drives the local rig. |
| `ENVIRONMENT_URL` | variable | Optional link shown on the GitHub deployment. |
| `SMOKE_URL` | variable | Where `smoke-test.sh` probes. Inferred for `docker://` targets. |
| `EXTRACT_CREDENTIALS` | secret | Only if you can't use OIDC. Prefer OIDC. |

**Environment gates**, applied by the bootstrap:

| Env | Reviewers | Wait | Deploys from |
| --- | --- | --- | --- |
| dev | *none* — automatic | — | main |
| qa | `@qa` | — | main |
| stage | `@qa` + `@release-managers` | — | main |
| uat | `@release-managers` + `@business-owners` | — | main |
| prod | `@release-managers` + `@security` | **10 min** | main |
| train | `@release-managers` + `@training` | — | main |

All gated environments set `prevent_self_review` — whoever requested a promotion
cannot also approve it.

**Pinned actions.** Every action is pinned to a full commit SHA (tags are mutable;
SHAs are not). Dependabot bumps them weekly, which is what makes pinning sustainable.

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

The base image `python:3.12-slim` is pinned by **digest** for the same reason.

### The reference app

Hello World that can prove which build of itself is talking.

| Endpoint | Returns |
| --- | --- |
| `GET /` | The greeting, plus a chain-of-custody card (HTML). |
| `GET /healthz` | `{"status":"ok"}`. Liveness only — used by the container healthcheck. |
| `GET /version` | Provenance. **200** if verified, **409** if not. |
| `GET /extract` | The extract + schema-contract validation. **422** if the contract is violated. |

`/version` payload:

```json
{
  "environment": "prod",
  "release_tag": "v0.1.7",
  "version": "0.1.7",
  "commit": "dfbb7d8",
  "built_at": "2026-07-11T23:25:59-06:00",
  "expected_sha256": "0c0e8fbe...",   // what the promotion manifest says
  "observed_sha256": "0c0e8fbe...",   // what the bytes on disk actually hash to
  "self_verified": true
}
```

[provenance.py](src/app/provenance.py) reads `BUILDINFO` (baked in at build time),
reads `RUNTIME` (written by the deploy from the promotion manifest), then **re-hashes
the tarball it was unpacked from** and compares. Unknown never counts as verified — a
service that cannot prove its identity must not claim it has.

The healthcheck deliberately probes `/healthz`, **not** `/version`: an unverified
service should be reachable-but-failing so you can inspect it, not invisible.

### The Docker rig

Six long-lived containers that are deployment **targets**, not applications.

| Env | Port | Container |
| --- | --- | --- |
| dev | 8081 | `automation1-dev` |
| qa | 8082 | `automation1-qa` |
| stage | 8083 | `automation1-stage` |
| uat | 8084 | `automation1-uat` |
| prod | 8085 | `automation1-prod` |
| train | 8086 | `automation1-train` |

The image carries the Python runtime and the pinned dependencies — but **no
application code**. Code only ever arrives as the promoted tarball, installed by
`deploy.sh`, so the rig cannot cheat. Containers idle in a "waiting for a deployment"
loop until something is installed, because *"no release deployed"* is a real state a
freshly provisioned environment is in.

Runs as a non-root user (uid 10001) with `no-new-privileges`.

### Scripts

| Script | Runs where | State |
| --- | --- | --- |
| [build.sh](scripts/build.sh) | CI + release | ✅ Deterministic tarball into `dist/`. |
| [test.sh](scripts/test.sh) | CI + release | ✅ pytest + shell/YAML self-checks. |
| [smoke-test.sh](scripts/smoke-test.sh) | After every deploy | ✅ Liveness → provenance → digest match → schema contract. |
| [deploy.sh](scripts/deploy.sh) | Every environment | ⚠️ Real for `docker://`; **stub for your target**. |
| [demo.sh](scripts/demo.sh) | Local only | ✅ Build once, promote through all six. |
| [bootstrap-github.ps1](scripts/bootstrap-github.ps1) | Local, once | ✅ Platform hardening via the API. |

Contract between build and deploy: **exactly one `dist/*.tar.gz`.**

---

## Security posture

Enforced by the platform, not by convention.

**GitHub-native.** CodeQL (`security-extended`, scanning both `python` and the
`actions` language — so it audits *these workflows* for CI/CD vulnerabilities);
dependency review (blocks PRs adding vulnerable or badly-licensed deps, denies
AGPL/GPL); secret scanning **with push protection**, which rejects the push containing
a credential rather than alerting after it has leaked; Dependabot across
`github-actions`, `pip` and `docker`; OpenSSF Scorecard nightly.

**Commercial.** Snyk (SCA + SAST) and SonarQube with a quality gate. Flag-gated, so
the pipeline is green until licences land. All scanners emit SARIF into a single
Security tab, enforced by a single ruleset.

**Supply chain.** Every release artifact carries **SLSA build provenance**.
`_deploy.yml` verifies it — with `--signer-workflow` bound to `_build.yml` in this
repo — before *every* deploy. An artifact someone uploaded by hand has no attestation
and cannot reach any environment. The digest is re-checked at promote time, at deploy
time, and by the service itself at startup.

**Platform.** Read-only default `GITHUB_TOKEN`; workflows cannot approve PRs; actions
restricted to an allow-list (the "verified creator" badge is *not* blanket-trusted);
every action pinned to a full commit SHA; `harden-runner` on every job; deny-by-default
`permissions: {}` with per-job opt-in; timeouts on every job; concurrency groups that
**queue** deploys rather than cancelling them mid-flight.

**Branch ruleset on `main`.** PR required; 2 approvals; code-owner review;
`ci-passed` required; dismiss stale reviews; require last-push approval; signed
commits; linear history; squash-only; no force-push; no deletion — and it applies to
admins.

Report vulnerabilities via [SECURITY.md](SECURITY.md).

---

## Design decisions, and why

**`dev` has no manifest file.** It always runs the latest release by definition, so
recording that in git would mean pushing to `main` from CI — which would require a
bypass hole in the branch ruleset. That's a real weakening of protection, bought in
exchange for a fact we can already derive. Promotion to QA reads the latest release
directly.

**Promotion is a PR, not a button.** A button leaves an entry in an audit log nobody
reads. A PR is reviewable, blameable, revertable, and lets CODEOWNERS enforce
*different* approvers per environment without any custom code.

**The build must be reproducible.** `built_at` comes from the **commit** timestamp,
never `date`. An earlier version used the wall clock and produced a different digest
on every rebuild — which would silently make the digests in promotion manifests
unverifiable. This is the single easiest way to hollow the system out; guard it.

**Scanners are `continue-on-error`, but their findings still block.** A scanner
outage should not wedge the pipeline, so the scan *step* tolerates failure — but the
SARIF upload means the resulting alerts still block merges via the code-scanning
ruleset. Availability and enforcement are decoupled on purpose.

**Deploys queue, they don't cancel.** `cancel-in-progress: false` on the deploy
concurrency group. Cancelling a half-finished production deploy is worse than waiting
for it.

**`prevent_self_review`.** Separation of duties enforced by the platform rather than
by policy documents.

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Every PR blocked, nobody can approve | CODEOWNERS names a team that doesn't exist | Create the teams, or point CODEOWNERS at real handles. **[Step 1](#1-create-the-teams-do-this-first).** |
| Promotion PR has **no checks at all** | Promotion GitHub App not configured | **[Step 4](#4-create-the-promotion-github-app).** Until then, promotion PRs merge unverified. |
| `Dependency review is not supported on this repository` | Dependency graph disabled | Enable Dependabot alerts. *(Already done here — but this is what bit us first.)* |
| PR blocked on `ci-passed` that never ran | CI hasn't reported on this repo yet | Expected on a fresh repo. That's the gate working, not a bug. |
| `$'\r': command not found` on a runner | A `.sh` file got CRLF endings | [.gitattributes](.gitattributes) prevents this. Don't remove it. |
| Deploy fails: `gh attestation verify` | Artifact wasn't built by `_build.yml`, or was altered after release | **Working as designed.** Investigate before overriding. |
| Deploy fails on digest mismatch | The release asset changed after promotion was approved | **Working as designed.** Someone replaced the artifact. |
| `/version` returns 409 | Running bytes ≠ promoted digest | **Working as designed.** The service is refusing to vouch for itself. |
| Promote fails: *"nothing to promote"* | Target already runs that tag, or source is empty | Not an error. Refusing a no-op PR. |
| Snyk/Sonar show as **skipped** | Flag-gated, not enabled | **[Step 5](#5-turn-on-the-commercial-scanners).** Skipped ≠ passing. |
| `demo.sh`: *"environment is not running"* | Rig isn't up | `docker compose up -d --build` |
| Node 20 deprecation warnings | Upstream actions haven't bumped yet | Cosmetic. Dependabot will pick it up. |

Deeper design notes: [docs/PIPELINE.md](docs/PIPELINE.md).
