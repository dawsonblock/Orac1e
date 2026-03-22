from pathlib import Path

from runtime.arbiter.contract_eval import ContractEvaluator
from runtime.arbiter.decision_gate import DecisionGate
from runtime.events.schemas import PublishDecision, ValidationReport


def test_contract_eval_denies_default_branch_push():
    evaluator = ContractEvaluator(Path('domains/code/contracts.yaml'))
    res = evaluator.evaluate({
        'target_branch': 'main',
        'action_type': 'pr.open',
        'changed_paths': ['src/x.py'],
        'changed_code_files_count': 1,
        'targeted_tests_passed': True,
        'test_runtime_network': False,
        'path_outside_workspace': False,
    })
    assert not res.ok


def test_decision_gate_prefers_draft_pr_when_no_added_tests():
    gate = DecisionGate()
    report = ValidationReport(
        task_id='task_x',
        attempt_id='attempt_x',
        preflight_passed=True,
        lint_passed=True,
        targeted_tests_passed=True,
        full_tests_passed=None,
        risk_score=0.2,
        confidence=0.8,
        changed_files=['src/x.py'],
    )
    decision = gate.decide(report, patch_has_tests=False)
    assert decision.mode == 'draft_pr'
