from pathlib import Path

from reposentry.checks.repo_hygiene import check_repo_hygiene


def test_flags_missing_required_files(tmp_path: Path) -> None:
    findings = check_repo_hygiene(tmp_path)

    rule_paths = {f.path for f in findings}
    assert rule_paths == {"README.md", "LICENSE", ".gitignore"}


def test_passes_when_all_files_present(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_text("# demo\n")
    (tmp_path / "LICENSE").write_text("MIT\n")
    (tmp_path / ".gitignore").write_text("__pycache__/\n")

    findings = check_repo_hygiene(tmp_path)

    assert findings == []
