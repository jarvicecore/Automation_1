"""Finding data model and output rendering (text, markdown, JSON)."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from enum import Enum


class Severity(str, Enum):
    ERROR = "error"
    WARNING = "warning"

    @property
    def rank(self) -> int:
        return {"warning": 1, "error": 2}[self.value]


@dataclass(frozen=True, slots=True)
class Finding:
    severity: Severity
    rule_id: str
    path: str
    message: str
    line: int | None = None


def render_text(findings: list[Finding]) -> str:
    if not findings:
        return "reposentry: no findings."
    lines = []
    for f in findings:
        loc = f"{f.path}:{f.line}" if f.line else f.path
        lines.append(f"[{f.severity.value.upper()}] {f.rule_id} {loc} - {f.message}")
    return "\n".join(lines)


def render_markdown(findings: list[Finding]) -> str:
    if not findings:
        return "### reposentry results\n\n:white_check_mark: No findings.\n"
    header = (
        "### reposentry results\n\n| Severity | Rule | Location | Message |\n|---|---|---|---|\n"
    )
    rows = []
    for f in findings:
        loc = f"`{f.path}:{f.line}`" if f.line else f"`{f.path}`"
        icon = ":x:" if f.severity is Severity.ERROR else ":warning:"
        rows.append(f"| {icon} {f.severity.value} | `{f.rule_id}` | {loc} | {f.message} |")
    return header + "\n".join(rows) + "\n"


def render_json(findings: list[Finding]) -> str:
    return json.dumps([asdict(f) for f in findings], indent=2)


def max_severity(findings: list[Finding]) -> Severity | None:
    if not findings:
        return None
    return max((f.severity for f in findings), key=lambda s: s.rank)
