# Walkthrough

A hands-on tour in two parts: the **local** half, which you can run right
now with nothing but Docker, and the **GitHub** half, which exercises the
approval gates, CODEOWNERS, and attestation checks that only make sense
against a real repository. For what each piece is *for*, see
[`docs/USE_CASES.md`](USE_CASES.md); for how it's built, see
[`docs/ARCHITECTURE.md`](ARCHITECTURE.md).

## Part 1: the local rig

### Prerequisites

- Docker and Docker Compose
- This repo cloned locally

### Bring up six empty environments

```bash
git clone <this-repo>
cd Automation_1
docker compose up -d --build
```

Six containers start: `automation1-dev`, `-qa`, `-stage`, `-uat`, `-prod`,
`-train`, on ports 8081–8086. Each one carries the Python runtime and
pinned dependencies but **no application code** — they idle, waiting for an
artifact to be installed into them, exactly like a freshly provisioned
host. Curl any of them right now and you'll get a connection refused or an
empty response; that's the correct starting state, not a bug.

### Build once, promote through all six

```bash
./scripts/demo.sh
```

Watch the output. It does four things, in order:

1. **Builds exactly one artifact** (`scripts/build.sh`) and prints its
   SHA256 digest.
2. **Promotes that same artifact** through `dev → qa → stage → uat → prod → train`
   — for each one, `deploy.sh` installs it and `smoke-test.sh` verifies it
   came up correctly. No step in this loop rebuilds anything; the same
   tarball is installed six times.
3. Prints the receipt:

   ```text
   SIX ENVIRONMENTS, ONE DIGEST
   ENV     PORT    VERIFIED  DIGEST RUNNING
   dev     8081    yes       0c0e8fbe4428fd223c0af5df0f914abf...
   qa      8082    yes       0c0e8fbe4428fd223c0af5df0f914abf...
   stage   8083    yes       0c0e8fbe4428fd223c0af5df0f914abf...
   uat     8084    yes       0c0e8fbe4428fd223c0af5df0f914abf...
   prod    8085    yes       0c0e8fbe4428fd223c0af5df0f914abf...
   train   8086    yes       0c0e8fbe4428fd223c0af5df0f914abf...
   ```

   Every digest in that column is identical. That's not a coincidence to
   take on faith — it's the same file, `sha256sum`'d fresh at each
   environment.

4. Prints the URLs. Open any of them, e.g. <http://localhost:8085> — you'll
   see "Hello, World," which environment you're looking at, and a
   chain-of-custody card showing the release tag, the digest the pipeline
   promoted, and the digest the service actually observed on disk. They
   match, and the page tells you so.

### Break it on purpose

A verification step that can't fail is decoration. Prove this one can:

```bash
docker exec -u root automation1-prod sh -c 'echo tampered >> /opt/app/artifact.tar.gz'
docker restart automation1-prod
sleep 3

curl -s http://localhost:8085/version
# {"self_verified": false, ...}  — and the HTTP status is 409, not 200
```

Then run the same check the real pipeline runs after every deploy:

```bash
ARTIFACT_SHA256="<the digest demo.sh printed>" \
EXTRACT_TARGET=docker://automation1-prod \
  ./scripts/smoke-test.sh prod
# exits 1 — this deploy would have been blocked
```

The service isn't trusting anyone's word about what it's running — it
re-hashes the artifact file on disk and compares that against what the
promotion manifest said should be there. Tamper with the file, and the
comparison fails, visibly. See
[`src/app/provenance.py`](../src/app/provenance.py) and
[the tamper-detection use case](USE_CASES.md#detecting-a-tampered-deployment)
for what's actually happening here.

**Restore it** by re-running the demo (it rebuilds and reinstalls a clean
artifact everywhere):

```bash
./scripts/demo.sh
```

**Tear down** when you're done:

```bash
docker compose down -v
```

### What this does and doesn't prove

The local rig proves the *data path*: build once, install the same bytes
six times, detect tampering when it happens. The *control plane* —
approval gates, CODEOWNERS, SLSA attestation, promotion pull requests —
runs on GitHub, not in Docker, and is exercised by the workflows in Part 2.
The two halves meet in exactly one place: `deploy.sh` is the same script in
both.

## Part 2: the GitHub side

This part assumes the repository is set up per
[`docs/SETUP.md`](SETUP.md) — the branch ruleset applied, environments
configured. If you're reading this against a fresh clone that hasn't been
bootstrapped yet, do that first; the steps below describe the intended,
fully-configured behavior.

### Shipping a change

1. Branch, make a change, open a PR against `main`.
2. Watch the **CI** check run: build, test, CodeQL, dependency review,
   `reposentry`, and whatever commercial scanners are enabled. It reports
   as a single `ci-passed` check regardless of how many jobs ran
   underneath — see [ADR pattern in ARCHITECTURE.md](ARCHITECTURE.md#trust-boundaries-and-permissions)
   for why aggregating matters.
3. Merge. Watch the **Release** workflow run in the Actions tab: it builds
   once, attests provenance, publishes a GitHub Release (tag `v0.1.<run>`),
   and deploys `dev` automatically.
4. Open the new release under the repo's **Releases** tab. It carries the
   artifact, a `.sha256` digest file, and a CycloneDX SBOM. Note the line
   in the release notes showing how to verify its attestation with
   `gh attestation verify`.

### Promoting a release

1. **Actions → Promote → Run workflow.**
2. Choose a target environment reachable from what's currently deployed
   (the workflow's dropdown only offers valid next hops — you can't jump
   `qa` straight to `prod`) and enter a change reference.
3. Watch the workflow verify the source environment's digest and
   provenance, then open a pull request. Open that PR — it shows exactly
   which release tag is moving where, and why (your change reference, in
   the PR body).
4. Approve and merge it as the environment's CODEOWNERS. Watch **Deploy**
   pick up the manifest change and run — it re-verifies digest and
   provenance independently before installing anything, then runs the
   smoke test.
5. Check the job summary on that deploy run: it records the release,
   digest, actor, and confirms provenance was verified.

### Rolling back

Find the previous promotion PR for the environment in question (`git log
environments/prod.yaml` from a local clone, or the file's history on
GitHub) and revert its merge commit. Open that as a PR, get it approved,
merge it. `deploy.yml` runs exactly as it would for a forward promotion —
same verification, same smoke test — just pointed at the previous release
tag. See [the rollback use case](USE_CASES.md#an-emergency-rollback) for
why this is deliberately not a separate code path.

### Checking the security posture

Repo → **Security** tab. Every scanner in [`_security.yml`](../.github/workflows/_security.yml)
that emits SARIF (CodeQL, Snyk once enabled, Scorecard) lands its findings
here, in one place, regardless of which job produced them. The nightly
[Scheduled Security](../.github/workflows/scheduled-security.yml) run adds
a drift report to its own job summary — see
[the drift-monitoring use case](USE_CASES.md#monitoring-drift).
