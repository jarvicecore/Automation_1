# Automation_1

Enterprise CI/CD on GitHub Actions for a data-extract workload, built on one
rule:

> **Build once. Promote the same bytes. Never rebuild.**

CI produces a single artifact when code merges to `main`. That exact
artifact — identified by its SHA256 — travels through every environment by
pull request, re-verified at every hop. If Prod is running `v0.1.42`, those
are bit-for-bit the same bytes QA signed off on, and the running service can
prove it about itself.

```text
dev ──► qa ──► stage ──► uat ──► prod ──► train
 │       └───────────────────────────────────┘
 │                    promotion PRs
 └── automatic on merge to main
```

## See it work, in two minutes

The repo ships a **six-environment rig** in Docker. Each container is a
deployment *target*, not an application — it comes up empty and idles until
an artifact is installed into it, exactly like a freshly provisioned host.

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

Open <http://localhost:8085>. It says **Hello, World** — and then proves
which build of itself is saying it. `/version` returns **409** if the
service can't prove its own identity, so it fails its own deployment rather
than quietly serving traffic. Prove it:

```bash
docker exec -u root automation1-prod sh -c 'echo tampered >> /opt/app/artifact.tar.gz'
docker restart automation1-prod && sleep 3
./scripts/smoke-test.sh prod        # exits 1 — deployment blocked
```

Re-run `./scripts/demo.sh` to restore it; `docker compose down -v` to tear
down.

**What this does and doesn't prove.** The local rig proves the *data path*:
build once, install the same bytes six times, detect tampering. The
*control plane* — approval gates, CODEOWNERS, SLSA attestation, promotion
PRs — runs on GitHub and is exercised by the real workflows, not by Docker.
The full walkthrough of both halves is in
[`docs/WALKTHROUGH.md`](docs/WALKTHROUGH.md).

## Current status

| | Status |
| --- | --- |
| CI | ✅ green — build, tests, CodeQL (`actions` + `python`), dependency review, `reposentry`, security gate |
| Reference app + six-environment Docker rig | ✅ real and working — `./scripts/demo.sh` |
| `tools/reposentry` (in-house secrets/hygiene scanner) | ✅ integrated into the security gate |
| `bootstrap-github.ps1` | ❌ not run yet — see [`docs/SETUP.md`](docs/SETUP.md) |
| Promotion GitHub App | ❌ not created — promotion PRs get no checks until it is |
| Snyk / SonarQube | ❌ off (flag-gated; pipeline is green without them) |
| `deploy.sh` | ⚠️ real for the Docker rig; stub for a real target |

Full setup instructions, in order: [`docs/SETUP.md`](docs/SETUP.md).

## Repository layout

```text
.github/workflows/    ci · release · promote · deploy · scheduled-security
                       _build · _security · _deploy  (reusable)
environments/         Promotion topology + per-environment deployment state
src/app/               The reference service (FastAPI, self-verifying)
tests/                 11 tests, including the tamper-detection path
scripts/               build · test · deploy · smoke-test · demo · bootstrap
docker/                The environment image — runtime only, no app code
tools/reposentry/      In-repo secret/hygiene scanner, run by the security gate
docs/                  Architecture, use cases, walkthrough, setup, ADRs
```

Full annotated layout, workflow-by-workflow reference, and endpoint docs:
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Documentation

| | |
| --- | --- |
| [**docs/ARCHITECTURE.md**](docs/ARCHITECTURE.md) | How it's built — components, diagrams, trust boundaries, the three-gate verification model. |
| [**docs/USE_CASES.md**](docs/USE_CASES.md) | Concrete scenarios: shipping a change, promoting, rolling back, catching tampering, drift. |
| [**docs/WALKTHROUGH.md**](docs/WALKTHROUGH.md) | Hands-on, step by step — locally and on GitHub. |
| [**docs/SETUP.md**](docs/SETUP.md) | Cold start to a fully configured, enforced pipeline. |
| [**docs/OPERATIONS.md**](docs/OPERATIONS.md) | Configuration reference and troubleshooting. |
| [**docs/adr/**](docs/adr/) | Why each non-obvious decision was made. |
| [**SECURITY.md**](SECURITY.md) | Security posture and vulnerability reporting. |
| [**CONTRIBUTING.md**](CONTRIBUTING.md) | Dev setup and how to propose a change. |

## License

[MIT](LICENSE)
