from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from apps.patch_worker import PatchWorker
from apps.planner_worker import PlannerWorker
from apps.validation_worker import ValidationWorker
from runtime.common.config import GitHubAppConfig, RuntimePaths, SandboxConfig
from runtime.common.ids import stable_task_id
from runtime.events.schemas import IssueTask
from runtime.github.app_auth import GitHubAppAuth
from runtime.github.branch_protection import BranchProtectionInspector
from runtime.github.checks_api import GitHubChecksAPI
from runtime.github.client import GitHubClient
from runtime.github.comments_api import GitHubCommentsAPI
from runtime.github.pr_api import GitHubPullRequestAPI
from runtime.github.publish_guard import PublishGuard
from runtime.workspace.branch_namer import branch_name
from runtime.workspace.git_publisher import GitPublisher
from runtime.workspace.repo_cache import RepoCache
from runtime.workspace.worktree_manager import WorktreeManager


def load_issue(path: Path) -> IssueTask:
    payload = json.loads(path.read_text(encoding='utf-8'))
    return IssueTask(
        task_id=stable_task_id(payload['repo'], int(payload['issue_number'])),
        repo=payload['repo'],
        repo_url=payload['repo_url'],
        issue_number=int(payload['issue_number']),
        base_ref=payload.get('base_ref', 'main'),
        title=payload['title'],
        body=payload['body'],
        labels=payload.get('labels', ['agent:fix']),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description='Run the bounded code-agent pipeline and publish through a GitHub App')
    parser.add_argument('issue_json', type=Path)
    parser.add_argument('--runtime-root', type=Path, default=Path('.runtime'))
    parser.add_argument('--attempt', type=int, default=1)
    args = parser.parse_args()

    task = load_issue(args.issue_json)
    paths = RuntimePaths.under(args.runtime_root.resolve())
    repo_cache = RepoCache(paths.cache_root)
    worktrees = WorktreeManager(paths.workspaces_root)
    repo_dir = repo_cache.ensure_repo_cached(task.repo_url)
    repo_cache.fetch_ref(repo_dir, task.base_ref)
    branch = branch_name(task.issue_number, args.attempt)
    workspace = worktrees.create_worktree(repo_dir, task.base_ref, branch)

    gh_cfg = GitHubAppConfig.from_env()
    gh_auth = GitHubAppAuth(gh_cfg)
    token = gh_auth.installation_token()
    gh_client = GitHubClient(gh_cfg.api_url, token, dry_run=gh_cfg.dry_run)
    checks = GitHubChecksAPI(gh_client, task.repo)
    comments = GitHubCommentsAPI(gh_client, task.repo)
    prs = GitHubPullRequestAPI(gh_client, task.repo)
    protection = BranchProtectionInspector(gh_client, task.repo)
    publish_guard = PublishGuard()
    publisher = GitPublisher()

    planner = PlannerWorker()
    patcher = PatchWorker()
    validator = ValidationWorker(sandbox=SandboxConfig.from_env())

    head_sha = publisher.current_head_sha(workspace)
    check = checks.create_check_run(name='code-agent-runtime', head_sha=head_sha, status='in_progress')
    check_id = None
    if isinstance(check.payload, dict):
        raw_id = check.payload.get('id')
        if isinstance(raw_id, int):
            check_id = raw_id

    try:
        plan, parsed = planner.run(workspace, task, attempt_index=args.attempt)
        patch, guard, trace = patcher.run(workspace, plan, parsed)
        if patch is None:
            attempted = ', '.join(trace.attempted_files) or 'none'
            comments.create_issue_comment(
                issue_number=task.issue_number,
                body=f'Agent rejected patch build: {guard.message}\n\nAttempted files: {attempted}',
            )
            if check_id is not None:
                checks.update_check_run(
                    check_run_id=check_id,
                    status='completed',
                    conclusion='failure',
                    output={'title': 'Patch build failed', 'summary': guard.message},
                )
            return 1

        report, _details = validator.run(workspace, plan, patch)
        if not report.targeted_tests_passed or not report.preflight_passed:
            summary = '\n'.join(report.notes)
            comments.create_issue_comment(issue_number=task.issue_number, body='Agent validation failed.\n\n' + summary)
            if check_id is not None:
                checks.update_check_run(
                    check_run_id=check_id,
                    status='completed',
                    conclusion='failure',
                    output={'title': 'Validation failed', 'summary': summary[:65000]},
                )
            return 1

        protection_summary = protection.summarize(task.base_ref)
        publish = publish_guard.decide(base_branch=task.base_ref, protection=protection_summary)
        if not publish.allow:
            comments.create_issue_comment(issue_number=task.issue_number, body='Agent publish guard blocked PR creation.\n\n' + publish.reason)
            if check_id is not None:
                checks.update_check_run(
                    check_run_id=check_id,
                    status='completed',
                    conclusion='failure',
                    output={'title': 'Publish blocked', 'summary': publish.reason},
                )
            return 1

        push = publisher.push_branch(workspace, branch)
        if not push.ok:
            comments.create_issue_comment(issue_number=task.issue_number, body=f'Agent could not push candidate branch: {push.message}')
            if check_id is not None:
                checks.update_check_run(
                    check_run_id=check_id,
                    status='completed',
                    conclusion='failure',
                    output={'title': 'Push failed', 'summary': push.message},
                )
            return 1

        required_checks = ', '.join(protection_summary.required_status_checks) or 'none'
        pr_body = '\n'.join([
            'Automated candidate patch from code-agent-runtime.',
            '',
            f'Summary: {patch.summary}',
            f'Confidence: {report.confidence:.3f}',
            f'Risk score: {report.risk_score:.3f}',
            '',
            'Validation notes:',
            *[f'- {note}' for note in report.notes],
            '',
            'Branch protection summary:',
            f'- protected: {protection_summary.protected}',
            f'- requires_pull_request_reviews: {protection_summary.requires_pull_request_reviews}',
            f'- required_status_checks: {required_checks}',
            f'- source: {protection_summary.source}',
            f'- publish_guard: {publish.reason}',
        ])
        pr_response = prs.open_draft_pr(
            title=f'[agent] {task.title}',
            head=branch,
            base=task.base_ref,
            body=pr_body,
            draft=True,
        )
        if check_id is not None:
            checks.update_check_run(
                check_run_id=check_id,
                status='completed',
                conclusion='success',
                output={'title': 'Draft PR opened', 'summary': str(pr_response.payload)[:65000]},
            )
        return 0
    finally:
        if gh_cfg.dry_run:
            pass
        else:
            worktrees.remove_worktree(workspace)
            if workspace.exists():
                shutil.rmtree(workspace, ignore_errors=True)


if __name__ == '__main__':
    raise SystemExit(main())
