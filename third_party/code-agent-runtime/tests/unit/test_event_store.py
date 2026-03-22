import time
from pathlib import Path

from runtime.events.schemas import RuntimeEvent
from runtime.events.store import EventStore


def test_event_store_is_append_only(tmp_path: Path):
    store = EventStore(tmp_path / 'events.sqlite3')
    event = RuntimeEvent('evt_1', 'task_a', 'attempt_a', 'x', int(time.time() * 1000), {'a': 1})
    store.append(event)
    items = store.list_by_task('task_a')
    assert len(items) == 1
    assert items[0].payload['a'] == 1
