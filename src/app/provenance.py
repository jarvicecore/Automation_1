"""Where the service works out what it actually is.

This module is the point of the whole demo. A service that merely *claims* a
version is worthless -- anyone can print a string. This one:

  1. Reads BUILDINFO, which was baked into the artifact at build time.
  2. Reads RUNTIME, which the deploy wrote from the promotion manifest.
  3. Re-computes the SHA256 of the tarball it was actually unpacked from.
  4. Reports whether (3) matches what the pipeline *said* it deployed.

If self_verified is false, the bytes running here are not the bytes the
promotion PR was approved with, and you should care a great deal.
"""

from __future__ import annotations

import hashlib
import os
from dataclasses import dataclass, asdict
from pathlib import Path

APP_ROOT = Path(os.environ.get("APP_ROOT", "/opt/app/current"))
ARTIFACT = Path(os.environ.get("ARTIFACT_PATH", "/opt/app/artifact.tar.gz"))


def _read_kv(path: Path) -> dict[str, str]:
    """Parse a trivial key=value file. Missing file is not an error -- it just
    means we are running outside a deployment (a dev box, or a unit test)."""
    if not path.is_file():
        return {}
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip()
    return out


def _sha256(path: Path) -> str | None:
    if not path.is_file():
        return None
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


@dataclass(frozen=True)
class Provenance:
    environment: str
    release_tag: str
    version: str
    commit: str
    built_at: str

    # What the pipeline says we are.
    expected_sha256: str
    # What we actually are, computed from the artifact on disk.
    observed_sha256: str | None
    # Do those agree?
    self_verified: bool

    def as_dict(self) -> dict:
        return asdict(self)


def load() -> Provenance:
    build = _read_kv(APP_ROOT / "BUILDINFO")
    runtime = _read_kv(APP_ROOT / "RUNTIME")

    expected = runtime.get("artifact_sha256", "")
    observed = _sha256(ARTIFACT)

    # Deliberately strict: unknown does NOT count as verified. A service that
    # cannot prove its own identity must not claim it has.
    verified = bool(expected) and bool(observed) and expected == observed

    return Provenance(
        environment=runtime.get("environment", os.environ.get("ENV_NAME", "local")),
        release_tag=runtime.get("release_tag", "none"),
        version=build.get("version", "0.0.0-dev"),
        commit=build.get("commit", "unknown"),
        built_at=build.get("built_at", "unknown"),
        expected_sha256=expected or "unknown",
        observed_sha256=observed,
        self_verified=verified,
    )
