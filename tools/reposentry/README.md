# reposentry

An in-repo tool, not a dependency of the reference app in `src/app/`. Pipeline
tooling and the promoted workload are kept in separate packages deliberately —
see `docs/adr/` in the repo root — so nothing here ever ends up inside the
artifact that gets built once and promoted through every environment.

Three checks, zero runtime dependencies (stdlib only):

- **secrets** — pattern-matches for committed credentials (AWS/GitHub/Slack
  tokens, private key blocks, generic `key = "..."` assignments). A narrower,
  faster complement to GitHub's own secret scanning, run in-band as part of
  the security gate rather than as a separate integration.
- **large-files** — flags files over a size threshold, a common vector for
  accidentally committed dumps or binaries.
- **hygiene** — checks for a README, LICENSE, and `.gitignore` at the repo
  root.

## Usage

```bash
pip install -e ".[dev]"
reposentry .                                   # scan cwd, human-readable text
reposentry . --format markdown --fail-on error  # what the security gate runs
reposentry src --checks secrets                 # scope to one check / one directory
```

Exit code is non-zero once a finding at or above `--fail-on` severity is
present. See `.github/workflows/_security.yml` for how this is wired into CI.
