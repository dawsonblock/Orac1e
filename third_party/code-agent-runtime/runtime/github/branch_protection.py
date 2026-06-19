from __future__ import annotations

from dataclasses import dataclass, field

from runtime.github.client import GitHubClient


@dataclass(frozen=True)
class BranchProtectionSummary:
    branch: str
    protected: bool
    requires_pull_request_reviews: bool
    required_status_checks: list[str] = field(default_factory=list)
    enforce_admins: bool = False
    restrictions_enabled: bool = False
    allow_force_pushes: bool = False
    allow_deletions: bool = False
    source: str = 'api'


class BranchProtectionInspector:
    def __init__(self, client: GitHubClient, repo: str):
        self.client = client
        self.repo = repo

    def get_default_branch(self) -> str:
        response = self.client.get(f'/repos/{self.repo}')
        payload = response.payload if isinstance(response.payload, dict) else {}
        return str(payload.get('default_branch', 'main'))

    def summarize(self, branch: str) -> BranchProtectionSummary:
        branch_resp = self.client.get(f'/repos/{self.repo}/branches/{branch}')
        branch_payload = branch_resp.payload if isinstance(branch_resp.payload, dict) else {}
        protected = bool(branch_payload.get('protected', False))
        if branch_payload.get('dry_run'):
            return BranchProtectionSummary(branch=branch, protected=False, requires_pull_request_reviews=False, source='dry_run')

        protection = branch_payload.get('protection') or {}
        required_checks = protection.get('required_status_checks') or {}
        pr_reviews = protection.get('required_pull_request_reviews') or {}
        restrictions = protection.get('restrictions')
        allow_force = protection.get('allow_force_pushes') or {}
        allow_delete = protection.get('allow_deletions') or {}
        admins = protection.get('enforce_admins') or {}
        contexts = required_checks.get('contexts') or []
        return BranchProtectionSummary(
            branch=branch,
            protected=protected,
            requires_pull_request_reviews=bool(pr_reviews),
            required_status_checks=[str(item) for item in contexts],
            enforce_admins=bool(admins.get('enabled', False)) if isinstance(admins, dict) else bool(admins),
            restrictions_enabled=bool(restrictions),
            allow_force_pushes=bool(allow_force.get('enabled', False)) if isinstance(allow_force, dict) else bool(allow_force),
            allow_deletions=bool(allow_delete.get('enabled', False)) if isinstance(allow_delete, dict) else bool(allow_delete),
        )
