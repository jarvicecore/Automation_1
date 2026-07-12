"""Unit tests. Run by scripts/test.sh, so a failure here blocks the merge."""

from __future__ import annotations

import hashlib
import tarfile
import io

import pytest
from fastapi.testclient import TestClient

from app import extract, provenance
from app.main import app

client = TestClient(app)


# --- the extract contract ---------------------------------------------------


def test_extract_satisfies_its_own_contract():
    assert extract.validate(extract.run()) == []


def test_extract_still_says_hello():
    rows = extract.run()["rows"]
    assert any(r["greeting"] == "Hello, World" for r in rows)


def test_validate_catches_schema_drift():
    """The contract check has to actually fail on a bad extract, or it is
    decoration. Assert the failure path, not just the happy one."""
    bad = {"schema": ["id", "greeting"], "row_count": 1, "rows": [{"id": 1}]}
    problems = extract.validate(bad)
    assert any("schema drifted" in p for p in problems)
    assert any("missing columns" in p for p in problems)


def test_validate_catches_empty_extract():
    problems = extract.validate({"schema": extract.SCHEMA, "row_count": 0, "rows": []})
    assert any("zero rows" in p for p in problems)


def test_validate_catches_lying_row_count():
    problems = extract.validate(
        {"schema": extract.SCHEMA, "row_count": 99, "rows": extract.GREETINGS}
    )
    assert any("disagrees" in p for p in problems)


# --- endpoints --------------------------------------------------------------


def test_healthz():
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_extract_endpoint():
    r = client.get("/extract")
    assert r.status_code == 200
    body = r.json()
    assert body["contract_valid"] is True
    assert body["row_count"] == len(extract.GREETINGS)


def test_index_renders():
    r = client.get("/")
    assert r.status_code == 200
    assert "Hello, World." in r.text


# --- provenance: the part that actually matters -----------------------------


def _fake_deployment(tmp_path, expected_digest: str, actual_bytes: bytes):
    """Build a fake deployed environment on disk: an artifact tarball, plus the
    BUILDINFO/RUNTIME files that build and deploy would have written."""
    root = tmp_path / "current"
    root.mkdir()
    (root / "BUILDINFO").write_text(
        "name=automation1\nversion=1.2.3\ncommit=abc123\nbuilt_at=2026-01-01T00:00:00Z\n"
    )
    (root / "RUNTIME").write_text(
        f"environment=qa\nrelease_tag=v1.2.3\nartifact_sha256={expected_digest}\n"
    )
    artifact = tmp_path / "artifact.tar.gz"
    artifact.write_bytes(actual_bytes)
    return root, artifact


def test_version_verifies_when_digest_matches(tmp_path, monkeypatch):
    payload = b"pretend this is a tarball"
    digest = hashlib.sha256(payload).hexdigest()
    root, artifact = _fake_deployment(tmp_path, digest, payload)

    monkeypatch.setattr(provenance, "APP_ROOT", root)
    monkeypatch.setattr(provenance, "ARTIFACT", artifact)

    p = provenance.load()
    assert p.self_verified is True
    assert p.environment == "qa"
    assert p.release_tag == "v1.2.3"
    assert p.observed_sha256 == p.expected_sha256

    assert client.get("/version").status_code == 200


def test_version_refuses_when_artifact_was_swapped(tmp_path, monkeypatch):
    """The whole point. If the bytes on disk are not the bytes the pipeline said
    it promoted, the service must refuse to claim it is verified -- and /version
    must return 409 so the smoke test fails the deployment."""
    approved = hashlib.sha256(b"the artifact QA approved").hexdigest()
    root, artifact = _fake_deployment(tmp_path, approved, b"something else entirely")

    monkeypatch.setattr(provenance, "APP_ROOT", root)
    monkeypatch.setattr(provenance, "ARTIFACT", artifact)

    p = provenance.load()
    assert p.self_verified is False
    assert p.observed_sha256 != p.expected_sha256

    r = client.get("/version")
    assert r.status_code == 409
    assert r.json()["self_verified"] is False


def test_unknown_digest_is_not_treated_as_verified(tmp_path, monkeypatch):
    """Absence of evidence is not evidence of integrity. A missing artifact must
    read as unverified, never as 'probably fine'."""
    root = tmp_path / "current"
    root.mkdir()
    (root / "RUNTIME").write_text("environment=prod\nrelease_tag=v9\nartifact_sha256=\n")

    monkeypatch.setattr(provenance, "APP_ROOT", root)
    monkeypatch.setattr(provenance, "ARTIFACT", tmp_path / "does-not-exist.tar.gz")

    p = provenance.load()
    assert p.self_verified is False
    assert client.get("/version").status_code == 409
