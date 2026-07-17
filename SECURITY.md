# Security policy

## Supported versions

This is a reference/template project (0.x); only the latest release on
`main` is supported.

## Reporting a vulnerability

Please report suspected vulnerabilities privately via GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability)
feature on this repository (Security tab → "Report a vulnerability") rather
than opening a public issue. Include reproduction steps and the affected
version if known. You should expect an initial response within 5 business
days.

## What this repo scans for, and what it doesn't

The `security.yml` workflow runs CodeQL (SAST), `bandit` (Python-specific
SAST), `pip-audit` (dependency CVEs), `gitleaks` and `reposentry` (secret
scanning), a dependency-review gate on PRs, and generates a CycloneDX SBOM
on every run. It does not include container/image scanning (no container
image is built here) or DAST (no deployed endpoint exists to scan) — see
[`docs/adr/`](docs/adr/) for the reasoning behind the controls that are
included, and add those two when this template is adapted for a project
that ships an image or a live service.
