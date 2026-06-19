from __future__ import annotations

import json
from pathlib import Path

from runtime.github.client import GitHubClient, GitHubResponse
from runtime.validation.artifact_collector import ArtifactCollector


class CommentReporter:
    def __init__(self, collector: ArtifactCollector):
        self.collector = collector

    def post_failure_comment(self, *, task_id: str, attempt_id: str, reason: str, notes: list[str], markdown_summary: str | None = None) -> Path:
        return self.collector.write_bundle(
            f'comment_bundle_{task_id}_{attempt_id}.zip',
            {
                'comment.json': json.dumps(
                    {
                        'type': 'comment',
                        'task_id': task_id,
                        'attempt_id': attempt_id,
                        'reason': reason,
                        'notes': notes,
                    },
                    indent=2,
                    sort_keys=True,
                ),
                'summary.md': markdown_summary or '',
            },
        )


class GitHubCommentsAPI:
    def __init__(self, client: GitHubClient, repo: str):
        self.client = client
        self.repo = repo

    def create_issue_comment(self, *, issue_number: int, body: str) -> GitHubResponse:
        return self.client.post(f'/repos/{self.repo}/issues/{issue_number}/comments', {'body': body})
