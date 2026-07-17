# Contributing

## Local setup

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
```

Run the same checks CI runs:

```bash
BUILD_VERSION=0.0.0-dev ./scripts/build.sh   # produces dist/*.tar.gz
BUILD_VERSION=0.0.0-dev ./scripts/test.sh    # pytest + shell/YAML self-checks
```

`tools/reposentry` is a separate package (see
[ADR 0005](docs/adr/0005-pipeline-tooling-kept-outside-src.md)) with its own
setup:

```bash
cd tools/reposentry
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
ruff check src tests && ruff format --check src tests && mypy && pytest
```

To exercise the full pipeline locally, including promotion between
environments: [`docs/WALKTHROUGH.md`](docs/WALKTHROUGH.md).

## Before opening a PR

- `./scripts/test.sh` passes locally.
- If you touched `tools/reposentry`: `ruff`, `mypy`, and `pytest` all pass
  there too.
- If you touched a workflow file: every third-party (and first-party)
  `uses:` reference is pinned to a full commit SHA, not a tag — see
  [ADR 0009](docs/adr/0009-pin-every-action-to-a-full-commit-sha.md). New
  jobs default to `permissions: contents: read` (or nothing) unless they
  specifically need more.
- If you touched `scripts/build.sh`: verify it's still deterministic by
  building the same commit twice and diffing the digest — see
  [ADR 0004](docs/adr/0004-deterministic-reproducible-builds.md). This
  won't be caught by `bash -n` or a type checker; it has to be run.

The [PR template](.github/pull_request_template.md) asks for a risk level,
data impact, and a rollback note — fill it in for real. For anything that
will reach Prod, the "change reference" field isn't decoration: it's what
ends up in the promotion PR's audit trail.

## Conventions

- Shell scripts: `set -euo pipefail`, and keep `deploy.sh` free of
  `if [ "$TARGET_ENV" = "prod" ]`-style branches — see
  [`docs/SETUP.md`](docs/SETUP.md#6-point-deploysh-at-your-real-target) for
  why that's load-bearing, not stylistic.
- Workflow changes that touch the CI/CD control plane itself (anything
  under `.github/workflows/`, `.github/CODEOWNERS`, `.github/rulesets/`)
  are reviewed by whoever [`CODEOWNERS`](.github/CODEOWNERS) names for
  that path — currently `@jarvicecore` in solo mode; see
  [ADR 0008](docs/adr/0008-solo-mode-vs-enterprise-codeowners.md).
- A new architecturally-significant decision (not every PR — the ones with
  a real alternative that got rejected, and a reason) gets a new file in
  [`docs/adr/`](docs/adr/), numbered sequentially, in the same
  Status/Context/Decision/Consequences shape as the existing ones.
- New checks under `tools/reposentry/src/reposentry/checks/` follow the
  existing shape: a pure function `(root: Path, ...) -> list[Finding]`,
  covered by tests using `tmp_path`.

## Reporting a security issue

Do not open a public issue. See [`SECURITY.md`](SECURITY.md).
