from __future__ import annotations

from integration.shared_py.models import ProposeRequest


def build_issue_task_kwargs(req: ProposeRequest) -> dict:
    title = req.task.strip().splitlines()[0][:120]
    return {
        'task_id': req.run_id,
        'repo': req.repo_name,
        'repo_url': f'local://{req.repo_name}',
        'issue_number': 0,
        'base_ref': 'HEAD',
        'title': title,
        'body': req.task.strip(),
        'labels': [req.mode],
    }
