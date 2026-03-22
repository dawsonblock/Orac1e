from __future__ import annotations

from dataclasses import dataclass

from .schemas import RuntimeEvent
from .store import EventStore


@dataclass(frozen=True)
class AttemptReplay:
    attempt_id: str
    event_types: list[str]
    event_count: int


class ReplayEngine:
    def __init__(self, store: EventStore):
        self.store = store

    def replay_attempt(self, attempt_id: str) -> AttemptReplay:
        events = self.store.list_by_attempt(attempt_id)
        return AttemptReplay(
            attempt_id=attempt_id,
            event_types=[e.event_type for e in events],
            event_count=len(events),
        )
