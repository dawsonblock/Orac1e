from __future__ import annotations

import time
from pathlib import Path

import jwt
import requests

from runtime.common.config import GitHubAppConfig


class GitHubAppAuthError(RuntimeError):
    pass


class GitHubAppAuth:
    def __init__(self, config: GitHubAppConfig):
        self.config = config

    def _private_key(self) -> str:
        if not self.config.private_key_path.exists():
            raise GitHubAppAuthError(f'private key not found: {self.config.private_key_path}')
        return self.config.private_key_path.read_text(encoding='utf-8')

    def app_jwt(self) -> str:
        now = int(time.time())
        return jwt.encode(
            {
                'iat': now - 60,
                'exp': now + 540,
                'iss': self.config.app_id,
            },
            self._private_key(),
            algorithm='RS256',
        )

    def installation_token(self) -> str:
        if self.config.dry_run:
            return 'dry-run-installation-token'
        jwt_token = self.app_jwt()
        response = requests.post(
            f'{self.config.api_url.rstrip('/')}/app/installations/{self.config.installation_id}/access_tokens',
            headers={
                'Accept': 'application/vnd.github+json',
                'Authorization': f'Bearer {jwt_token}',
                'X-GitHub-Api-Version': '2022-11-28',
            },
            timeout=30,
        )
        if response.status_code >= 400:
            raise GitHubAppAuthError(f'installation token request failed with {response.status_code}: {response.text}')
        payload = response.json()
        token = payload.get('token')
        if not token:
            raise GitHubAppAuthError('installation token missing from GitHub response')
        return token
