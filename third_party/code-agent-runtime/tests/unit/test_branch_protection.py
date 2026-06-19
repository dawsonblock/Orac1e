from runtime.github.branch_protection import BranchProtectionInspector
from runtime.github.client import GitHubResponse


class FakeClient:
    def get(self, path: str):
        if path == '/repos/acme/repo':
            return GitHubResponse(200, {'default_branch': 'main'}, {})
        if path == '/repos/acme/repo/branches/main':
            return GitHubResponse(200, {
                'name': 'main',
                'protected': True,
                'protection': {
                    'required_status_checks': {'contexts': ['ci/test', 'lint']},
                    'required_pull_request_reviews': {'required_approving_review_count': 1},
                    'enforce_admins': {'enabled': True},
                    'restrictions': {'users': []},
                    'allow_force_pushes': {'enabled': False},
                    'allow_deletions': {'enabled': False},
                },
            }, {})
        raise AssertionError(path)


def test_branch_protection_summary_reads_protected_branch():
    inspector = BranchProtectionInspector(FakeClient(), 'acme/repo')
    assert inspector.get_default_branch() == 'main'
    summary = inspector.summarize('main')
    assert summary.protected is True
    assert summary.requires_pull_request_reviews is True
    assert summary.required_status_checks == ['ci/test', 'lint']
    assert summary.enforce_admins is True
