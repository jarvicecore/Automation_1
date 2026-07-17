from pathlib import Path

from reposentry.checks.large_files import check_large_files


def test_flags_file_over_threshold(tmp_path: Path) -> None:
    big = tmp_path / "dump.sql"
    big.write_bytes(b"0" * (2 * 1024 * 1024))

    findings = check_large_files(tmp_path, max_size_mb=1.0)

    assert len(findings) == 1
    assert findings[0].rule_id == "hygiene.large-file"
    assert findings[0].path == "dump.sql"


def test_allows_file_under_threshold(tmp_path: Path) -> None:
    small = tmp_path / "notes.txt"
    small.write_bytes(b"0" * 1024)

    findings = check_large_files(tmp_path, max_size_mb=1.0)

    assert findings == []
