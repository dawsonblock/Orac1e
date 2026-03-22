from __future__ import annotations

from runtime.events.schemas import IssueTask


class TaskRouter:
    def __init__(self, trigger_label: str = "agent:fix"):
        self.trigger_label = trigger_label

    def should_process(self, task: IssueTask) -> bool:
        return self.trigger_label in task.labels
