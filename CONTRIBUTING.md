# Contributing

## Local setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

## Before opening a PR

```bash
ruff check src tests
ruff format --check src tests
mypy
pytest
```

All four run in CI (`.github/workflows/ci.yml`) and must pass before merge;
running them locally first is just faster feedback. `security.yml` runs
CodeQL, `bandit`, `pip-audit`, `gitleaks`, and `reposentry` itself against
every PR — see [`SECURITY.md`](SECURITY.md) for what's covered.

## Conventions

- Type hints are required (`mypy --strict`); avoid `Any` where a real type
  is available.
- New checks under `src/reposentry/checks/` should follow the existing
  shape: a pure function `(root: Path, ...) -> list[Finding]` with no
  side effects, plus tests using `tmp_path`.
- Workflow changes: pin any new third-party `uses:` reference to a full
  commit SHA (see [`docs/adr/0001`](docs/adr/0001-pin-actions-to-full-commit-sha.md))
  and default new jobs to `permissions: contents: read` unless they
  specifically need more.
