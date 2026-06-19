from runtime.github.branch_protection import BranchProtectionSummary
from runtime.github.publish_guard import PublishGuard


def test_publish_guard_forces_draft_when_protected():
    guard = PublishGuard()
    decision = guard.decide(
        base_branch='main',
        protection=BranchProtectionSummary(
            branch='main',
            protected=True,
            requires_pull_request_reviews=True,
            required_status_checks=['ci'],
        ),
    )
    assert decision.allow
    assert decision.force_draft


def test_publish_guard_blocks_release_branch_base():
    guard = PublishGuard()
    decision = guard.decide(base_branch='release', protection=None)
    assert not decision.allow
