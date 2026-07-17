# Setup

Taking this repository from "cloned" to "the pipeline is non-optional and
enforced" is six steps, done once. This repo is currently configured for
**solo mode** — see step 2 for what that means and why it exists.

## 1. Merge the platform PR, if you haven't

If you're setting this up from a fork or a fresh copy where the platform
workflows are still on a branch:

```bash
gh pr merge <pr-number> --squash
```

Do this **before** enabling the branch ruleset in step 2 — the ruleset
requires the `ci-passed` check to exist, which it can't until at least one
PR has run through CI.

## 2. Run the bootstrap script

[`scripts/bootstrap-github.ps1`](../scripts/bootstrap-github.ps1) applies
everything that makes the pipeline non-optional: the branch ruleset, the
six GitHub Environments and their approval gates, the read-only default
token, the Actions allow-list, and the promotion labels.

```powershell
./scripts/bootstrap-github.ps1 -Solo -DryRun   # preview, changes nothing
./scripts/bootstrap-github.ps1 -Solo           # apply
```

It's idempotent — re-running it after changing team names or environment
config is the normal way to update the platform config, not just the
first-run path. Calls that need a feature your GitHub plan doesn't have
warn rather than abort.

### Why solo mode exists, and what it costs

**GitHub will not let an account approve its own pull request.** If this
repo lives on a personal account (no teams available), the enterprise
ruleset's required 2 approving reviews, code-owner review, and
`prevent_self_review` would deadlock every PR — including every promotion
PR — permanently. `-Solo` applies
[`rulesets/main-solo.json`](../.github/rulesets/main-solo.json) instead of
[`main.json`](../.github/rulesets/main.json), relaxing exactly the four
controls that assume a second human exists:

| Control | Enterprise | `-Solo` |
| --- | --- | --- |
| Required approving reviews | 2 | **0** |
| Code-owner review | required | **not required** |
| `prevent_self_review` on environments | on | **off** — you approve your own deploys |
| Signed commits | required | **not required** |

Everything else stays identical and fully enforced: PR required to reach
`main` (no direct pushes, no force-push, no deletion), `ci-passed` required,
code-scanning alert threshold blocks merges, linear history, squash-only —
and **every environment past `dev` still requires your explicit approval
click before it deploys.** You're not skipping the gate; you're the only
person available to staff it. See
[ADR 0008](adr/0008-solo-mode-vs-enterprise-codeowners.md) for the full
reasoning.

Running the bootstrap **without** `-Solo` on a personal account is detected
and warns loudly rather than half-applying a config that would lock you
out.

**Moving to an org later:** move the repo, create the six teams named at
the bottom of [`CODEOWNERS`](../.github/CODEOWNERS), uncomment that block
and delete the solo block above it, then re-run the bootstrap **without**
`-Solo`. Nothing else changes.

## 3. Create the promotion GitHub App

**Do not skip this.** GitHub deliberately does not trigger workflows on
pull requests opened by the default `GITHUB_TOKEN` — a recursion guard.
Without an App-minted token, promotion PRs open with **zero status checks**
and can be merged completely unverified, which hollows out the entire
promotion model (see [ADR 0002](adr/0002-promotion-as-pull-request.md)).

1. Create a GitHub App in your org (or on your account) with:
   - **Contents:** Read and write
   - **Pull requests:** Read and write
2. Install it on this repository.
3. Generate a private key for it.
4. Repo → Settings → Secrets and variables → Actions:
   - Variable `PROMOTION_APP_ID` = the App's ID
   - Secret `PROMOTION_APP_PRIVATE_KEY` = the full `.pem` file contents

## 4. Turn on the commercial scanners (optional)

Snyk and SonarQube are wired into [`_security.yml`](../.github/workflows/_security.yml)
but **skipped** until explicitly enabled — a skipped scanner catches
nothing, and the pipeline is intentionally green without them so licensing
isn't a blocker to using everything else.

| Variable | Value | Enables |
| --- | --- | --- |
| `ENABLE_SNYK` | `true` | Snyk SCA + SAST (needs `secrets.SNYK_TOKEN`) |
| `ENABLE_SONAR` | `true` | SonarQube quality gate (needs `secrets.SONAR_TOKEN`, `vars.SONAR_HOST_URL`) |

Also update `sonar.projectKey` in
[`sonar-project.properties`](../sonar-project.properties) if enabling
SonarQube.

## 5. Configure each environment

Repo → Settings → Environments → *(dev, qa, stage, uat, prod, train)* →
add:

| Setting | Type | Purpose |
| --- | --- | --- |
| `EXTRACT_TARGET` | variable | Where this environment's artifact gets installed. `docker://automation1-qa` drives the local rig. |
| `ENVIRONMENT_URL` | variable | Optional — shown on the GitHub deployment record. |
| `SMOKE_URL` | variable | Where `smoke-test.sh` probes. Inferred automatically for `docker://` targets. |
| `EXTRACT_CREDENTIALS` | secret | Only if the target can't do OIDC — see below. |

The deploy job already has `id-token: write` granted. **Prefer OIDC
federation over `EXTRACT_CREDENTIALS`** wherever the target platform
supports it — a long-lived secret duplicated across six environments is
six places to leak it from. See
[ADR 0010](adr/0010-oidc-over-long-lived-deploy-credentials.md).

## 6. Point `deploy.sh` at your real target

[`src/app/`](../src/app/) is a real, working reference service — keep it
running until your own workload is ready. It costs nothing and keeps every
gate genuinely exercised rather than dormant.

[`scripts/deploy.sh`](../scripts/deploy.sh) dispatches on `EXTRACT_TARGET`:
a `docker://…` value drives the local rig; anything else falls through to
a clearly marked `TODO` where your real deploy call belongs (an Airflow /
ADF / Databricks Jobs API call, a scheduler registration, whatever "deploy"
means for your workload).

**Two rules in that script are load-bearing, not stylistic:**

- **`build.sh` must stay deterministic** — same commit in, same bytes out.
  See [ADR 0004](adr/0004-deterministic-reproducible-builds.md). Breaking
  this doesn't fail loudly; it just makes every digest check downstream
  meaningless.
- **`deploy.sh` must not branch on environment name.** No
  `if [ "$TARGET_ENV" = "prod" ]`. The entire value of this design is that
  by the time a deploy runs in Prod, the identical code path has already
  run, successfully, five times.

## Next

- Read [`docs/WALKTHROUGH.md`](WALKTHROUGH.md) to exercise what you just
  configured.
- Read [`docs/OPERATIONS.md`](OPERATIONS.md) for the full configuration
  reference and troubleshooting.
