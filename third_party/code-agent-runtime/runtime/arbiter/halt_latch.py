from __future__ import annotations


class HaltLatch:
    def __init__(self):
        self._latched = False
        self._reason = ''

    def trigger(self, reason: str) -> None:
        self._latched = True
        self._reason = reason

    @property
    def latched(self) -> bool:
        return self._latched

    @property
    def reason(self) -> str:
        return self._reason
