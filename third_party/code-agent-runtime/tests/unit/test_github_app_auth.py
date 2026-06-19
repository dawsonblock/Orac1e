from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from runtime.common.config import GitHubAppConfig
from runtime.github.app_auth import GitHubAppAuth
from runtime.github.client import GitHubClient
from runtime.github.comments_api import GitHubCommentsAPI
from runtime.github.pr_api import GitHubPullRequestAPI


def test_github_app_auth_builds_jwt(tmp_path: Path):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    key_path = tmp_path / 'app.pem'
    key_path.write_bytes(pem)
    auth = GitHubAppAuth(GitHubAppConfig(app_id='1234', private_key_path=key_path, installation_id=99, dry_run=True))
    token = auth.app_jwt()
    assert isinstance(token, str)
    assert token.count('.') == 2


def test_github_api_clients_support_dry_run():
    client = GitHubClient('https://api.github.com', token='x', dry_run=True)
    comment = GitHubCommentsAPI(client, 'acme/repo').create_issue_comment(issue_number=1, body='hello')
    pr = GitHubPullRequestAPI(client, 'acme/repo').open_draft_pr(title='x', head='a', base='main', body='b')
    assert comment.payload['dry_run'] is True
    assert pr.payload['payload']['draft'] is True
