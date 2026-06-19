from __future__ import annotations

import json
from pathlib import Path

from runtime.events.schemas import PatchArtifact, ValidationReport
from runtime.github.client import GitHubClient, GitHubResponse
from runtime.validation.artifact_collector import ArtifactCollector


class PullRequestReporter:
    def __init__(self, collector: ArtifactCollector):
        self.collector = collector

    def open_draft_pr(self, *, task_id: str, attempt_id: str, patch: PatchArtifact, report: ValidationReport, markdown_summary: str | None = None) -> Path:
        return self.collector.write_bundle(
            f'draft_pr_bundle_{task_id}_{attempt_id}.zip',
            {
                'draft_pr.json': json.dumps(
                    {
                        'type': 'draft_pr',
                        'task_id': task_id,
                        'attempt_id': attempt_id,
                        'title': f'Agent fix for {task_id}',
                        'summary': patch.summary,
                        'changed_files': patch.changed_files,
                        'risk_score': report.risk_score,
                        'confidence': report.confidence,
                        'notes': report.notes,
                    },
                    indent=2,
                    sort_keys=True,
                ),
                'summary.md': markdown_summary or '',
                'patch.diff': patch.diff_text,
            },
        )


class GitHubPullRequestAPI:
    def __init__(self, client: GitHubClient, repo: str):
        self.client = client
        self.repo = repo

    def open_draft_pr(
        self,
        *,
        title: str,
        head: str,
        base: str,
        body: str,
        draft: bool = True,
    ) -> GitHubResponse:
        payload = {
            'title': title,
            'head': head,
            'base': base,
            'body': body,
            'draft': draft,
        }
        return self.client.post(f'/repos/{self.repo}/pulls', payload)
