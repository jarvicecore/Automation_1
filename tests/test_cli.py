from pathlib import Path

import pytest

from reposentry.cli import main


def test_exits_zero_on_clean_repo(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    (tmp_path / "README.md").write_text("# demo\n")
    (tmp_path / "LICENSE").write_text("MIT\n")
    (tmp_path / ".gitignore").write_text("\n")
    (tmp_path / "app.py").write_text("print('hello')\n")

    exit_code = main([str(tmp_path)])

    assert exit_code == 0
    assert "no findings" in capsys.readouterr().out.lower()


def test_exits_nonzero_on_secret(tmp_path: Path) -> None:
    (tmp_path / "config.py").write_text('AWS_KEY = "AKIAABCDEFGHIJKLMNOP"\n')

    exit_code = main([str(tmp_path)])

    assert exit_code == 1


def test_fail_on_none_always_exits_zero(tmp_path: Path) -> None:
    (tmp_path / "config.py").write_text('AWS_KEY = "AKIAABCDEFGHIJKLMNOP"\n')

    exit_code = main([str(tmp_path), "--fail-on", "none"])

    assert exit_code == 0


def test_json_output_is_valid(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    import json

    (tmp_path / "config.py").write_text('AWS_KEY = "AKIAABCDEFGHIJKLMNOP"\n')

    main([str(tmp_path), "--format", "json", "--fail-on", "none"])

    payload = json.loads(capsys.readouterr().out)
    rule_ids = {finding["rule_id"] for finding in payload}
    assert "secrets.aws-access-key" in rule_ids


def test_checks_flag_scopes_to_secrets_only(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    # No README/LICENSE/.gitignore here — hygiene would normally flag this
    # directory, but --checks secrets should suppress those findings.
    (tmp_path / "app.py").write_text("print('hello')\n")

    exit_code = main([str(tmp_path), "--checks", "secrets", "--fail-on", "warning"])

    assert exit_code == 0
    assert "no findings" in capsys.readouterr().out.lower()


def test_github_step_summary_written(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    (tmp_path / "README.md").write_text("# demo\n")
    (tmp_path / "LICENSE").write_text("MIT\n")
    (tmp_path / ".gitignore").write_text("\n")
    summary_file = tmp_path / "summary.md"
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary_file))

    main([str(tmp_path), "--github-step-summary", "--fail-on", "none"])

    assert summary_file.exists()
    assert "reposentry results" in summary_file.read_text()
