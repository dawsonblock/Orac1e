from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any

import requests


@dataclass(frozen=True)
class GitHubResponse:
    status_code: int
    payload: dict[str, Any] | list[Any] | None
    headers: dict[str, Any]


class GitHubApiError(RuntimeError):
    pass


class GitHubClient:
    def __init__(self, api_url: str, token: str, dry_run: bool = True, *, max_retries: int = 2, backoff_seconds: float = 0.1, session: requests.Session | None = None):
        self.api_url = api_url.rstrip('/')
        self.token = token
        self.dry_run = dry_run
        self.max_retries = max_retries
        self.backoff_seconds = backoff_seconds
        self.session = session or requests.Session()
        self.session.headers.update({
            'Accept': 'application/vnd.github+json',
            'Authorization': f'Bearer {token}',
            'X-GitHub-Api-Version': '2022-11-28',
        })

    def _normalize(self, response: requests.Response) -> GitHubResponse:
        payload = None
        try:
            payload = response.json()
        except Exception:
            if getattr(response, 'text', ''):
                payload = {'raw': response.text}
        return GitHubResponse(response.status_code, payload, dict(response.headers))

    def _request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> GitHubResponse:
        if self.dry_run:
            return GitHubResponse(200, {'dry_run': True, 'path': path, 'payload': payload, 'method': method}, {})
        last_error: Exception | None = None
        for attempt in range(self.max_retries + 1):
            response = self.session.request(method, f'{self.api_url}{path}', json=payload)
            if response.status_code < 400:
                return self._normalize(response)
            if response.status_code in {429, 500, 502, 503, 504} and attempt < self.max_retries:
                retry_after = response.headers.get('Retry-After')
                delay = float(retry_after) if retry_after else self.backoff_seconds * (2 ** attempt)
                time.sleep(delay)
                continue
            last_error = GitHubApiError(f'{method} {path} failed with {response.status_code}: {response.text}')
            break
        raise last_error or GitHubApiError(f'{method} {path} failed')

    def get(self, path: str) -> GitHubResponse:
        return self._request('GET', path)

    def post(self, path: str, payload: dict[str, Any]) -> GitHubResponse:
        return self._request('POST', path, payload)

    def patch(self, path: str, payload: dict[str, Any]) -> GitHubResponse:
        return self._request('PATCH', path, payload)
