from __future__ import annotations

from typing import Any

from runtime.github.client import GitHubClient, GitHubResponse


class GitHubChecksAPI:
    def __init__(self, client: GitHubClient, repo: str):
        self.client = client
        self.repo = repo

    def create_check_run(
        self,
        *,
        name: str,
        head_sha: str,
        status: str,
        details_url: str | None = None,
        output: dict[str, Any] | None = None,
    ) -> GitHubResponse:
        payload: dict[str, Any] = {
            'name': name,
            'head_sha': head_sha,
            'status': status,
        }
        if details_url:
            payload['details_url'] = details_url
        if output:
            payload['output'] = output
        return self.client.post(f'/repos/{self.repo}/check-runs', payload)

    def update_check_run(
        self,
        *,
        check_run_id: int,
        status: str,
        conclusion: str | None = None,
        output: dict[str, Any] | None = None,
    ) -> GitHubResponse:
        payload: dict[str, Any] = {'status': status}
        if conclusion:
            payload['conclusion'] = conclusion
        if output:
            payload['output'] = output
        return self.client.patch(f'/repos/{self.repo}/check-runs/{check_run_id}', payload)
