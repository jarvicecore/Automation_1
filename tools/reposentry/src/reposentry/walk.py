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
    root: Path,
    excludes: frozenset[str] = frozenset(DEFAULT_EXCLUDES),
    exclude_paths: tuple[str, ...] = (),
) -> Iterator[Path]:
    """Walk root, yielding files.

    exclude_paths are relative-path prefixes (e.g. "tools/reposentry/tests")
    for excluding a specific subtree without excluding its directory name
    everywhere else in the tree -- unlike `excludes`, which matches a bare
    path component ("tests") anywhere it appears.
    """
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if any(part in excludes or part.endswith(".egg-info") for part in path.parts):
            continue
        rel = path.relative_to(root).as_posix()
        if any(rel == p or rel.startswith(f"{p}/") for p in exclude_paths):
            continue
        yield path
