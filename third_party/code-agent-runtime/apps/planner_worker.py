from __future__ import annotations

from pathlib import Path

from runtime.common.ids import stable_attempt_id
from runtime.events.schemas import EditPlan, IssueTask
from runtime.intake.issue_parser import IssueParser
from runtime.planning.edit_plan import EditPlanner
from runtime.planning.issue_localizer import IssueLocalizer


class PlannerWorker:
    def __init__(self):
        self.parser = IssueParser()
        self.localizer = IssueLocalizer()
        self.planner = EditPlanner()

    def run(self, repo_root: Path, task: IssueTask, attempt_index: int = 1) -> tuple[EditPlan, object]:
        parsed = self.parser.parse(task.title, task.body)
        attempt_id = stable_attempt_id(task.task_id, attempt_index)
        candidate_files, test_targets = self.localizer.localize(repo_root, parsed)
        plan = self.planner.build(task, parsed, attempt_id, candidate_files, test_targets)
        return plan, parsed
