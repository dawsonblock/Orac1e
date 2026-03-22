from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from .schemas import RuntimeEvent


class EventStore:
    def __init__(self, db_path: Path):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)

    def _init_db(self) -> None:
        with self._connect() as con:
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS events (
                    row_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_id TEXT UNIQUE NOT NULL,
                    task_id TEXT NOT NULL,
                    attempt_id TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    ts_ms INTEGER NOT NULL,
                    payload_json TEXT NOT NULL
                )
                """
            )
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS artifacts (
                    artifact_id TEXT PRIMARY KEY,
                    task_id TEXT NOT NULL,
                    attempt_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    path TEXT NOT NULL
                )
                """
            )

    def append(self, event: RuntimeEvent) -> None:
        with self._connect() as con:
            con.execute(
                "INSERT INTO events(event_id, task_id, attempt_id, event_type, ts_ms, payload_json) VALUES (?, ?, ?, ?, ?, ?)",
                (event.event_id, event.task_id, event.attempt_id, event.event_type, event.ts_ms, json.dumps(event.payload, sort_keys=True)),
            )

    def list_by_task(self, task_id: str) -> list[RuntimeEvent]:
        return self._list("SELECT event_id, task_id, attempt_id, event_type, ts_ms, payload_json FROM events WHERE task_id=? ORDER BY row_id", (task_id,))

    def list_by_attempt(self, attempt_id: str) -> list[RuntimeEvent]:
        return self._list("SELECT event_id, task_id, attempt_id, event_type, ts_ms, payload_json FROM events WHERE attempt_id=? ORDER BY row_id", (attempt_id,))

    def _list(self, query: str, params: tuple[str, ...]) -> list[RuntimeEvent]:
        with self._connect() as con:
            rows = con.execute(query, params).fetchall()
        out = []
        for row in rows:
            out.append(RuntimeEvent(event_id=row[0], task_id=row[1], attempt_id=row[2], event_type=row[3], ts_ms=row[4], payload=json.loads(row[5])))
        return out
