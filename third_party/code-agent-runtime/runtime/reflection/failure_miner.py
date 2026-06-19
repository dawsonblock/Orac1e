from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field

from runtime.events.schemas import RuntimeEvent


@dataclass(frozen=True)
class FailurePattern:
    code: str
    count: int
    examples: list[str] = field(default_factory=list)


class FailureMiner:
    def mine(self, events: list[RuntimeEvent]) -> list[FailurePattern]:
        counter: Counter[str] = Counter()
        examples: dict[str, list[str]] = {}
        for event in events:
            payload = event.payload or {}
            code = str(payload.get('code') or payload.get('reason') or event.event_type)
            if event.event_type not in {'publish_decision', 'validation_failure', 'patch_guard_reject', 'contract_reject'}:
                continue
            counter[code] += 1
            examples.setdefault(code, [])
            if len(examples[code]) < 3:
                examples[code].append(str(payload.get('message') or payload.get('reason') or code))
        return [FailurePattern(code=code, count=count, examples=examples.get(code, [])) for code, count in counter.most_common()]
