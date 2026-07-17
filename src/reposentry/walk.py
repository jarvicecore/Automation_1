"""Shared filesystem walk helper, excludes VCS/dependency directories."""

from __future__ import annotations

from collections.abc import Iterator
from pathlib import Path

DEFAULT_EXCLUDES = {
    ".git",
    ".hg",
    ".svn",
    "__pycache__",
    ".venv",
    "venv",
    "node_modules",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    "dist",
    "build",
    ".egg-info",
}


def iter_files(
    root: Path, excludes: frozenset[str] = frozenset(DEFAULT_EXCLUDES)
) -> Iterator[Path]:
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if any(part in excludes or part.endswith(".egg-info") for part in path.parts):
            continue
        yield path
