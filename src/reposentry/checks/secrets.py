"""Detect obviously-committed secrets via pattern matching.

This is a lightweight, dependency-free complement to dedicated secret
scanners (e.g. gitleaks, run separately in CI) — it exists to demonstrate
the shift-left pattern of catching common leaks before they ever reach a
remote, not to replace an entropy-based scanner.
"""

from __future__ import annotations

import re
from pathlib import Path

from reposentry.report import Finding, Severity
from reposentry.walk import iter_files

# Binary/media extensions are skipped; scanning them wastes time and yields
# only false positives from arbitrary byte sequences.
_SKIP_SUFFIXES = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".ico",
    ".pdf",
    ".zip",
    ".gz",
    ".tar",
    ".woff",
    ".woff2",
    ".ttf",
    ".eot",
    ".mp4",
    ".mov",
    ".lock",
}

_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("secrets.aws-access-key", re.compile(r"AKIA[0-9A-Z]{16}")),
    (
        "secrets.aws-secret-key",
        re.compile(r"(?i)aws_secret_access_key\s*[:=]\s*['\"]?[A-Za-z0-9/+=]{40}['\"]?"),
    ),
    (
        "secrets.private-key-block",
        re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----"),
    ),
    ("secrets.slack-token", re.compile(r"xox[baprs]-[0-9A-Za-z-]{10,48}")),
    ("secrets.github-token", re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}")),
    (
        "secrets.generic-assignment",
        re.compile(
            r"(?i)\b(api[_-]?key|secret|token|password|passwd)\b\s*[:=]\s*"
            r"['\"][A-Za-z0-9/+_\-]{16,}['\"]"
        ),
    ),
)


def check_secrets(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    for path in iter_files(root):
        if path.suffix.lower() in _SKIP_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            for rule_id, pattern in _PATTERNS:
                if pattern.search(line):
                    findings.append(
                        Finding(
                            severity=Severity.ERROR,
                            rule_id=rule_id,
                            path=str(path.relative_to(root)),
                            line=lineno,
                            message="Possible committed secret matched pattern.",
                        )
                    )
    return findings
