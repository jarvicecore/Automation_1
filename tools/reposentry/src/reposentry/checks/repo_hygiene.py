"""Baseline repository hygiene checks (README, LICENSE, .gitignore)."""

from __future__ import annotations

from pathlib import Path

from reposentry.report import Finding, Severity

_REQUIRED_ROOT_FILES: tuple[tuple[str, Severity, str], ...] = (
    ("README.md", Severity.WARNING, "Missing README.md at repository root."),
    ("LICENSE", Severity.WARNING, "Missing LICENSE at repository root."),
    (".gitignore", Severity.WARNING, "Missing .gitignore at repository root."),
)


def check_repo_hygiene(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    for filename, severity, message in _REQUIRED_ROOT_FILES:
        if not (root / filename).is_file():
            findings.append(
                Finding(
                    severity=severity,
                    rule_id="hygiene.missing-file",
                    path=filename,
                    message=message,
                )
            )
    return findings
