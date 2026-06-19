from apps.reflection_worker import ReflectionWorker
from runtime.events.schemas import RuntimeEvent
from runtime.events.store import EventStore


def test_reflection_worker_stages_proposals(tmp_path):
    db = tmp_path / 'events.db'
    store = EventStore(db)
    store.append(RuntimeEvent(event_id='e1', task_id='t1', attempt_id='a1', event_type='validation_failure', ts_ms=1, payload={'code': 'pytest_failed', 'message': 'x'}))
    store.append(RuntimeEvent(event_id='e2', task_id='t1', attempt_id='a1', event_type='validation_failure', ts_ms=2, payload={'code': 'pytest_failed', 'message': 'y'}))
    worker = ReflectionWorker(db, tmp_path / 'index.json', tmp_path / 'stage')
    staged = worker.run('t1', 'a1')
    assert len(staged) == 1
    assert staged[0].exists()
