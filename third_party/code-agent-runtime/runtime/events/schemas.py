from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Literal


@dataclass(frozen=True)
class IssueTask:
    task_id: str
    repo: str
    repo_url: str
    issue_number: int
    base_ref: str
    title: str
    body: str
    labels: list[str]


@dataclass(frozen=True)
class EditPlan:
    task_id: str
    attempt_id: str
    candidate_files: list[str]
    hypotheses: list[str]
    test_targets: list[str]
    stop_after_n_failed_attempts: int = 2


@dataclass(frozen=True)
class PatchArtifact:
    task_id: str
    attempt_id: str
    patch_id: str = ""
    diff_text: str = ""
    changed_files: list[str] = field(default_factory=list)
    added_tests: list[str] = field(default_factory=list)
    rationale: str = ""
    summary: str = ""


@dataclass(frozen=True)
class ValidationReport:
    task_id: str
    attempt_id: str
    preflight_passed: bool
    lint_passed: bool
    targeted_tests_passed: bool
    full_tests_passed: bool | None
    risk_score: float
    confidence: float
    changed_files: list[str]
    notes: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class PublishDecision:
    task_id: str
    attempt_id: str
    mode: Literal["reject", "comment_only", "draft_pr", "pr"]
    reason: str


@dataclass(frozen=True)
class RuntimeEvent:
    event_id: str
    task_id: str
    attempt_id: str
    event_type: str
    ts_ms: int
    payload: dict[str, Any]

    @classmethod
    def from_obj(cls, *, event_id: str, task_id: str, attempt_id: str, event_type: str, ts_ms: int, obj: Any) -> "RuntimeEvent":
        payload = asdict(obj) if hasattr(obj, "__dataclass_fields__") else dict(obj)
        return cls(event_id=event_id, task_id=task_id, attempt_id=attempt_id, event_type=event_type, ts_ms=ts_ms, payload=payload)
