"""Command-line entry point for reposentry."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from reposentry.checks import check_large_files, check_repo_hygiene, check_secrets
from reposentry.report import (
    Finding,
    Severity,
    max_severity,
    render_json,
    render_markdown,
    render_text,
)

_CHECKS = {
    "secrets": lambda root, max_file_size_mb, exclude_paths: check_secrets(
        root, exclude_paths=exclude_paths
    ),
    "large-files": lambda root, max_file_size_mb, exclude_paths: check_large_files(
        root, max_size_mb=max_file_size_mb, exclude_paths=exclude_paths
    ),
    "hygiene": lambda root, max_file_size_mb, exclude_paths: check_repo_hygiene(root),
}


def _run_checks(
    root: Path, max_file_size_mb: float, checks: list[str], exclude_paths: tuple[str, ...]
) -> list[Finding]:
    findings: list[Finding] = []
    for name in checks:
        findings += _CHECKS[name](root, max_file_size_mb, exclude_paths)
    return findings


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="reposentry",
        description="Pre-merge repository hygiene and secret-leak scanner.",
    )
    parser.add_argument(
        "path", nargs="?", default=".", help="Directory to scan (default: current directory)."
    )
    parser.add_argument(
        "--format", choices=["text", "markdown", "json"], default="text", help="Output format."
    )
    parser.add_argument(
        "--fail-on",
        choices=["error", "warning", "none"],
        default="error",
        help="Minimum severity that causes a non-zero exit code (default: error).",
    )
    parser.add_argument(
        "--max-file-size-mb",
        type=float,
        default=5.0,
        help="Flag files larger than this size in MB (default: 5.0).",
    )
    parser.add_argument(
        "--github-step-summary",
        action="store_true",
        help="Also append the markdown report to $GITHUB_STEP_SUMMARY if set.",
    )
    parser.add_argument(
        "--checks",
        nargs="+",
        choices=sorted(_CHECKS),
        default=sorted(_CHECKS),
        help=(
            "Which checks to run (default: all). Useful for scoping hygiene "
            "checks, which assume `path` is the repo root, separately from "
            "secrets/large-files checks, which can run against a subdirectory."
        ),
    )
    parser.add_argument(
        "--exclude",
        nargs="+",
        default=[],
        metavar="PATH",
        help=(
            "Relative path prefixes to exclude from secrets/large-files checks "
            "(e.g. --exclude tools/reposentry/tests). Repeatable via multiple "
            "values. Unlike directory-name excludes, this only matches the "
            "given subtree, not that name anywhere in the tree."
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path(args.path).resolve()
    findings = _run_checks(
        root,
        max_file_size_mb=args.max_file_size_mb,
        checks=args.checks,
        exclude_paths=tuple(args.exclude),
    )

    renderer = {"text": render_text, "markdown": render_markdown, "json": render_json}[args.format]
    print(renderer(findings))

    if args.github_step_summary:
        summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary_path:
            with open(summary_path, "a", encoding="utf-8") as fh:
                fh.write(render_markdown(findings))

    if args.fail_on == "none":
        return 0

    worst = max_severity(findings)
    if worst is None:
        return 0
    threshold = Severity(args.fail_on)
    return 1 if worst.rank >= threshold.rank else 0


if __name__ == "__main__":
    sys.exit(main())
