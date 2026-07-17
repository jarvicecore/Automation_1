"""The 'extract' half of the data-extract service.

Canned data, deliberately: this repo's job is to prove the *pipeline*, and a
real source system would only add failure modes that have nothing to do with
promotion. Swap GREETINGS for a real query when you have a real source -- the
shape (rows + a schema contract + a row count) is what the smoke test asserts,
and that stays the same.
"""

from __future__ import annotations

from typing import Any

# The hat-tip. It still says hello -- in eight languages, with a schema.
GREETINGS: list[dict[str, Any]] = [
    {"id": 1, "language": "English", "code": "en", "greeting": "Hello, World"},
    {"id": 2, "language": "Español", "code": "es", "greeting": "Hola, Mundo"},
    {"id": 3, "language": "Français", "code": "fr", "greeting": "Bonjour, le Monde"},
    {"id": 4, "language": "Deutsch", "code": "de", "greeting": "Hallo, Welt"},
    {"id": 5, "language": "日本語", "code": "ja", "greeting": "こんにちは世界"},
    {"id": 6, "language": "हिन्दी", "code": "hi", "greeting": "नमस्ते दुनिया"},
    {"id": 7, "language": "العربية", "code": "ar", "greeting": "مرحبا بالعالم"},
    {"id": 8, "language": "Ελληνικά", "code": "el", "greeting": "Γειά σου Κόσμε"},
]

# The contract. Downstream consumers depend on these columns existing, so a
# change here is a breaking change -- which is exactly why the smoke test
# checks it on every environment after every deploy, rather than trusting that
# nobody would ever do that.
SCHEMA: list[str] = ["id", "language", "code", "greeting"]


def run() -> dict[str, Any]:
    rows = GREETINGS
    return {
        "schema": SCHEMA,
        "row_count": len(rows),
        "rows": rows,
    }


def validate(result: dict[str, Any]) -> list[str]:
    """Return a list of contract violations. Empty list means the extract is good.

    Used by both the unit tests and the post-deploy smoke test, so the thing CI
    checks and the thing production checks cannot drift apart.
    """
    problems: list[str] = []

    if result.get("schema") != SCHEMA:
        problems.append(f"schema drifted: expected {SCHEMA}, got {result.get('schema')}")

    rows = result.get("rows") or []
    if not rows:
        problems.append("extract returned zero rows")

    if result.get("row_count") != len(rows):
        problems.append(
            f"row_count {result.get('row_count')} disagrees with actual rows {len(rows)}"
        )

    for i, row in enumerate(rows):
        missing = [c for c in SCHEMA if c not in row]
        if missing:
            problems.append(f"row {i} missing columns: {missing}")

    return problems
