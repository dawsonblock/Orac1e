from __future__ import annotations

import os
import sys
from pathlib import Path

from integration.shared_py.models import ProposeRequest
from integration.shared_py.diff_utils import changed_line_count, enforce_path_budget
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


def run_hardened(req: ProposeRequest) -> dict:
    PlannerWorker, PatchWorker, ValidationWorker, IssueTask = _load_runtime()
    issue_task = IssueTask(**build_issue_task_kwargs(req))
    repo_root = Path(req.repo_path)

    planner = PlannerWorker()
    patcher = PatchWorker(max_attempts=3)
    validator = ValidationWorker()

    plan, parsed = planner.run(repo_root=repo_root, task=issue_task, attempt_index=1)
    patch, patch_result, trace = patcher.run(repo_root=repo_root, plan=plan, parsed=parsed)

    if patch is not None:
        violations = enforce_path_budget(patch.diff_text, req.constraints.allowed_paths)
        if violations:
            raise ValueError(f"patch touched blocked paths: {', '.join(violations)}")
        lines = changed_line_count(patch.diff_text)
        if lines > req.constraints.max_changed_lines:
            raise ValueError(f'patch exceeded max_changed_lines: {lines} > {req.constraints.max_changed_lines}')
        report, _ = validator.run(repo_root=repo_root, plan=plan, patch=patch)
    else:
        report = None

    return to_response(patch, report, trace, getattr(patch_result, 'message', None))
