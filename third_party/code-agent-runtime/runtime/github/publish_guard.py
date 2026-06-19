from __future__ import annotations

from dataclasses import dataclass

from runtime.github.branch_protection import BranchProtectionSummary


@dataclass(frozen=True)
class PublishGuardDecision:
    allow: bool
    force_draft: bool
    reason: str


class PublishGuard:
    DEFAULT_BLOCKED_BASES = {'master', 'release'}

    def decide(self, *, base_branch: str, protection: BranchProtectionSummary | None) -> PublishGuardDecision:
        if base_branch in self.DEFAULT_BLOCKED_BASES:
            return PublishGuardDecision(False, True, f'base branch {base_branch!r} is blocked by policy')
        if protection is None:
            return PublishGuardDecision(True, True, 'branch protection unavailable; forcing draft PR')
        if protection.allow_deletions or protection.allow_force_pushes:
            return PublishGuardDecision(True, True, 'base branch policy is permissive; forcing draft PR for review')
        if protection.protected or protection.requires_pull_request_reviews or protection.required_status_checks:
            return PublishGuardDecision(True, True, 'branch protection requires review and checks; draft PR enforced')
        return PublishGuardDecision(True, True, 'draft PR enforced by runtime policy')
