from __future__ import annotations

import argparse

from runtime.common.config import GitHubAppConfig
from runtime.github.app_auth import GitHubAppAuth
from runtime.github.branch_protection import BranchProtectionInspector
from runtime.github.client import GitHubClient


def main() -> int:
    parser = argparse.ArgumentParser(description='Inspect GitHub branch protection through the configured GitHub App')
    parser.add_argument('repo')
    parser.add_argument('--branch', default='')
    args = parser.parse_args()

    cfg = GitHubAppConfig.from_env()
    token = GitHubAppAuth(cfg).installation_token()
    client = GitHubClient(cfg.api_url, token, dry_run=cfg.dry_run)
    inspector = BranchProtectionInspector(client, args.repo)
    branch = args.branch or inspector.get_default_branch()
    summary = inspector.summarize(branch)
    print(summary)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
