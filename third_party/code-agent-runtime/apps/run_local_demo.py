from __future__ import annotations

import argparse
import json
from pathlib import Path

from apps.patch_worker import PatchWorker
from apps.planner_worker import PlannerWorker
from apps.reporter_worker import ReporterWorker
from apps.validation_worker import ValidationWorker
from runtime.common.ids import stable_task_id
from runtime.events.schemas import IssueTask


def load_issue(path: Path) -> IssueTask:
    payload = json.loads(path.read_text(encoding='utf-8'))
    return IssueTask(
        task_id=stable_task_id('local/repo', int(payload.get('issue_number', 1))),
        repo=payload.get('repo', 'local/repo'),
        repo_url=str(payload.get('repo_url', 'local')),
        issue_number=int(payload.get('issue_number', 1)),
        base_ref=payload.get('base_ref', 'main'),
        title=payload['title'],
        body=payload['body'],
        labels=payload.get('labels', ['agent:fix']),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description='Run the bounded code-agent pipeline locally against a repository path')
    parser.add_argument('repo_root', type=Path)
    parser.add_argument('issue_json', type=Path)
    parser.add_argument('--attempt', type=int, default=1)
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    task = load_issue(args.issue_json)

    planner = PlannerWorker()
    patcher = PatchWorker()
    validator = ValidationWorker()
    reporter = ReporterWorker(repo_root / '.agent_outbox', repo_root / 'domains' / 'code' / 'contracts.yaml')

    plan, parsed = planner.run(repo_root, task, attempt_index=args.attempt)
    patch, guard, trace = patcher.run(repo_root, plan, parsed)
    if patch is None:
        print({'status': 'patch_rejected', 'reason': guard.message, 'attempted_files': trace.attempted_files})
        return 1
    report, _details = validator.run(repo_root, plan, patch)
    decision, artifact = reporter.run(target_branch=f'agent/issue-{task.issue_number}-attempt-{args.attempt:02d}', task=task, plan=plan, patch=patch, report=report, attempt_index=args.attempt, attempted_files=trace.attempted_files)
    print({'decision': decision.mode, 'reason': decision.reason, 'artifact': str(artifact)})
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
