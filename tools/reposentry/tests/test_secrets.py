from pathlib import Path

from reposentry.checks.secrets import check_secrets


def test_detects_aws_access_key(tmp_path: Path) -> None:
    (tmp_path / "config.py").write_text('AWS_KEY = "AKIAABCDEFGHIJKLMNOP"\n')

    findings = check_secrets(tmp_path)

    assert len(findings) == 1
    assert findings[0].rule_id == "secrets.aws-access-key"
    assert findings[0].line == 1


def test_detects_private_key_block(tmp_path: Path) -> None:
    (tmp_path / "id_rsa").write_text(
        "-----BEGIN RSA PRIVATE KEY-----\nMIIB...\n-----END RSA PRIVATE KEY-----\n"
    )

    findings = check_secrets(tmp_path)

    assert any(f.rule_id == "secrets.private-key-block" for f in findings)


def test_detects_generic_secret_assignment(tmp_path: Path) -> None:
    (tmp_path / ".env").write_text('API_KEY="not_a_real_key_abcdefghijklmnopqrstuvwx"\n')

    findings = check_secrets(tmp_path)

    assert any(f.rule_id == "secrets.generic-assignment" for f in findings)


def test_ignores_clean_files(tmp_path: Path) -> None:
    (tmp_path / "app.py").write_text("def add(a, b):\n    return a + b\n")

    findings = check_secrets(tmp_path)

    assert findings == []


def test_skips_binary_extensions(tmp_path: Path) -> None:
    (tmp_path / "image.png").write_bytes(b"AKIAABCDEFGHIJKLMNOP" + b"\x00\x01\x02")

    findings = check_secrets(tmp_path)

    assert findings == []


def test_excludes_git_directory(tmp_path: Path) -> None:
    git_dir = tmp_path / ".git"
    git_dir.mkdir()
    (git_dir / "config").write_text('token = "AKIAABCDEFGHIJKLMNOP"\n')

    findings = check_secrets(tmp_path)

    assert findings == []


def test_exclude_paths_suppresses_matching_subtree(tmp_path: Path) -> None:
    fixtures = tmp_path / "tests"
    fixtures.mkdir()
    (fixtures / "test_secrets.py").write_text('AWS_KEY = "AKIAABCDEFGHIJKLMNOP"\n')
    (tmp_path / "config.py").write_text('AWS_KEY = "AKIAABCDEFGHIJKLMNOP"\n')

    findings = check_secrets(tmp_path, exclude_paths=("tests",))

    assert len(findings) == 1
    assert findings[0].path == "config.py"


def test_exclude_paths_matches_prefix_not_substring(tmp_path: Path) -> None:
    # "tests" must not accidentally exclude "tests_helpers.py" or similar.
    (tmp_path / "tests_helpers.py").write_text('AWS_KEY = "AKIAABCDEFGHIJKLMNOP"\n')

    findings = check_secrets(tmp_path, exclude_paths=("tests",))

    assert len(findings) == 1
