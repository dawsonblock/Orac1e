from runtime.events.schemas import RuntimeEvent
from runtime.reflection.failure_miner import FailureMiner
from runtime.reflection.proposal_builder import ReflectionProposalBuilder


def test_failure_miner_groups_repeated_failures():
    events = [
        RuntimeEvent(event_id='e1', task_id='t', attempt_id='a', event_type='validation_failure', ts_ms=1, payload={'code': 'pytest_failed', 'message': 'x'}),
        RuntimeEvent(event_id='e2', task_id='t', attempt_id='a', event_type='validation_failure', ts_ms=2, payload={'code': 'pytest_failed', 'message': 'y'}),
        RuntimeEvent(event_id='e3', task_id='t', attempt_id='a', event_type='contract_reject', ts_ms=3, payload={'reason': 'forbidden_paths'}),
        RuntimeEvent(event_id='e4', task_id='t', attempt_id='a', event_type='contract_reject', ts_ms=4, payload={'reason': 'forbidden_paths'}),
    ]
    patterns = FailureMiner().mine(events)
    assert patterns[0].count == 2
    proposals = ReflectionProposalBuilder().build('t', 'a', patterns)
    kinds = {p.proposal_type for p in proposals}
    assert 'new_test' in kinds
    assert 'policy_constraint' in kinds
