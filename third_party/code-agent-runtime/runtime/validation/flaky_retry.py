from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class FlakeAnalysis:
    is_flaky_signal: bool
    reason: str


class FlakyRetryPolicy:
    SIGNALS = [
        'flaky',
        'flake',
        'rerun',
        're-run',
        'timeout',
        'timed out',
        'connection reset',
        'temporary failure',
        'address already in use',
        'resource temporarily unavailable',
    ]

    def analyze(self, text: str) -> FlakeAnalysis:
        haystack = (text or '').lower()
        for signal in self.SIGNALS:
            if signal in haystack:
                return FlakeAnalysis(True, signal)
        return FlakeAnalysis(False, '')
