from __future__ import annotations

import difflib
import os
import sys
from pathlib import Path

from integration.shared_py.models import ProposeRequest
from integration.shared_py.diff_utils import changed_line_count, enforce_path_budget
from integration.shared_py.logging_utils import emit
from integration.worker_hardened.task_mapper import build_issue_task_kwargs
from integration.worker_hardened.result_mapper import to_response


def _code_agent_root() -> Path:
    value = os.environ.get('CODE_AGENT_REPO_PATH')
    if not value:
        raise RuntimeError('CODE_AGENT_REPO_PATH is not set')
    return Path(value).resolve()


def _load_runtime():
    root = _code_agent_root()
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))
    from apps.planner_worker import PlannerWorker
    from apps.patch_worker import PatchWorker
    from apps.validation_worker import ValidationWorker
    from runtime.events.schemas import IssueTask
    return PlannerWorker, PatchWorker, ValidationWorker, IssueTask


class _FallbackPatch:
    """Minimal duck-typed patch object returned by the heuristic fallback."""

    def __init__(self, diff_text: str, changed_files: list[str]) -> None:
        self.diff_text = diff_text
        self.changed_files = changed_files
        self.summary = f"heuristic fallback patch ({len(changed_files)} file(s))"


def _heuristic_fallback(
    repo_root: Path,
    trace: object,
    plan: object,
) -> _FallbackPatch | None:
    """Last-resort line-level heuristic patcher.

    When the structured patch search produces no patch, attempt simple
    line-by-line replacements inferred from the plan hypotheses against the
    files that the searcher already identified as candidates.

    Returns a ``_FallbackPatch`` if at least one file was changed, else None.
    """
    candidate_files: list[Path] = [
        repo_root / f
        for f in (getattr(trace, "attempted_files", None) or [])
        if (repo_root / f).is_file()
    ]

    # Extract (target, replacement) pairs from plan hypotheses
    hypotheses = getattr(plan, "hypotheses", None) or []
    edits: list[tuple[str, str]] = []
    for h in hypotheses:
        target = getattr(h, "target", None)
        replacement = getattr(h, "replacement", None)
        if target and replacement is not None:
            edits.append((str(target), str(replacement)))

    if not candidate_files or not edits:
        return None

    changed_files: list[str] = []
    full_diff_lines: list[str] = []

    for fpath in candidate_files:
        try:
            original = fpath.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        modified = original
        for target, replacement in edits:
            if target in modified:
                modified = modified.replace(target, replacement, 1)

        if modified == original:
            continue

        rel = str(fpath.relative_to(repo_root))
        diff = list(
            difflib.unified_diff(
                original.splitlines(keepends=True),
                modified.splitlines(keepends=True),
                fromfile=f"a/{rel}",
                tofile=f"b/{rel}",
            )
        )
        if diff:
            fpath.write_text(modified, encoding="utf-8")
            changed_files.append(rel)
            full_diff_lines.extend(diff)

    if not changed_files:
        return None

    return _FallbackPatch(
        diff_text="".join(full_diff_lines),
        changed_files=changed_files,
    )


def run_hardened(req: ProposeRequest) -> dict:
    PlannerWorker, PatchWorker, ValidationWorker, IssueTask = _load_runtime()
    issue_task = IssueTask(**build_issue_task_kwargs(req))
    repo_root = Path(req.repo_path)

    emit("propose", "start", run_id=req.run_id, worker="hardened")

    planner = PlannerWorker()
    patcher = PatchWorker(max_attempts=3)
    validator = ValidationWorker()

    plan, parsed = planner.run(repo_root=repo_root, task=issue_task, attempt_index=1)
    patch, patch_result, trace = patcher.run(repo_root=repo_root, plan=plan, parsed=parsed)

    if patch is None:
        emit(
            "propose",
            "structured_patch_empty",
            run_id=req.run_id,
            worker="hardened",
            attempted_files=getattr(trace, "attempted_files", []),
        )
        patch = _heuristic_fallback(repo_root, trace, plan)
        if patch is not None:
            emit(
                "propose",
                "fallback_patch_applied",
                run_id=req.run_id,
                worker="hardened",
                changed_files=patch.changed_files,
            )
        else:
            emit(
                "propose",
                "no_patch_produced",
                run_id=req.run_id,
                worker="hardened",
            )

    if patch is not None:
        violations = enforce_path_budget(patch.diff_text, req.constraints.allowed_paths)
        if violations:
            raise ValueError(f"patch touched blocked paths: {', '.join(violations)}")
        lines = changed_line_count(patch.diff_text)
        if lines > req.constraints.max_changed_lines:
            raise ValueError(f'patch exceeded max_changed_lines: {lines} > {req.constraints.max_changed_lines}')
        report, _ = validator.run(repo_root=repo_root, plan=plan, patch=patch)
        emit("propose", "success", run_id=req.run_id, worker="hardened")
    else:
        report = None
        emit("propose", "failed", run_id=req.run_id, worker="hardened")

    return to_response(patch, report, trace, getattr(patch_result, 'message', None))
