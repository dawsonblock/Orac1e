from __future__ import annotations

import argparse
import json
from pathlib import Path

from apps.reporter_worker import ReporterWorker
from runtime.common.ids import stable_task_id
from runtime.events.schemas import IssueTask
from runtime.orchestration.attempt_runner import AttemptRunner


def load_issue(path: Path) -> IssueTask:
    payload = json.loads(path.read_text(encoding='utf-8'))
    return IssueTask(
        task_id=stable_task_id(payload.get('repo', 'local/repo'), int(payload.get('issue_number', 1))),
        repo=payload.get('repo', 'local/repo'),
        repo_url=str(payload.get('repo_url', 'local')),
        issue_number=int(payload.get('issue_number', 1)),
        base_ref=payload.get('base_ref', 'main'),
        title=payload['title'],
        body=payload['body'],
        labels=payload.get('labels', ['agent:fix']),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description='Run the code-agent pipeline across multiple bounded attempts')
    parser.add_argument('repo_root', type=Path)
    parser.add_argument('issue_json', type=Path)
    parser.add_argument('--max-attempts', type=int, default=2)
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    task = load_issue(args.issue_json)
    runner = AttemptRunner()
    run_result = runner.run(repo_root, task, max_attempts=args.max_attempts)
    if not run_result.records:
        print({'status': 'no_attempts'})
        return 1
    final = run_result.records[-1]
    if run_result.best_patch is None or run_result.best_report is None:
        print({'status': 'no_valid_patch', 'attempts': len(run_result.records)})
        return 1
    reporter = ReporterWorker(repo_root / '.agent_outbox', repo_root / 'domains' / 'code' / 'contracts.yaml')
    decision, bundle_path = reporter.run(
        target_branch=f'agent/issue-{task.issue_number}-attempt-{final.attempt_index:02d}',
        task=task,
        plan=final.plan,
        patch=run_result.best_patch,
        report=run_result.best_report,
        attempt_index=final.attempt_index,
        attempted_files=final.attempted_files,
    )
    print({'decision': decision.mode, 'reason': decision.reason, 'bundle': str(bundle_path), 'attempts': len(run_result.records)})
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
