from runtime.arbiter.risk_score import RiskScorer
from runtime.events.schemas import PatchArtifact


def test_risk_score_penalizes_sensitive_paths():
    patch = PatchArtifact(task_id='t', attempt_id='a', patch_id='p', diff_text='', changed_files=['runtime/auth.py'], added_tests=[], rationale='r', summary='s')
    scorer = RiskScorer()
    risk = scorer.score(patch, preflight_ok=True, lint_ok=True, tests_ok=True, full_tests_ok=True)
    assert risk > 0.15
