"""Flag files that exceed a size threshold.

Oversized files are frequently accidental — build artifacts, database
dumps, or media committed by mistake — and are a common vector for
inadvertent secret or PII leakage.
"""

from __future__ import annotations

from pathlib import Path

from reposentry.report import Finding, Severity
from reposentry.walk import iter_files

DEFAULT_MAX_FILE_SIZE_MB = 5.0


def check_large_files(
    root: Path,
    max_size_mb: float = DEFAULT_MAX_FILE_SIZE_MB,
    exclude_paths: tuple[str, ...] = (),
) -> list[Finding]:
    max_bytes = int(max_size_mb * 1024 * 1024)
    findings: list[Finding] = []
    for path in iter_files(root, exclude_paths=exclude_paths):
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size > max_bytes:
            findings.append(
                Finding(
                    severity=Severity.WARNING,
                    rule_id="hygiene.large-file",
                    path=str(path.relative_to(root)),
                    message=(
                        f"File is {size / (1024 * 1024):.1f} MB, "
                        f"exceeds {max_size_mb} MB threshold."
                    ),
                )
            )
    return findings
