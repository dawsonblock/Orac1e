from __future__ import annotations

from runtime.events.schemas import EditPlan, IssueTask
from runtime.intake.issue_parser import ParsedIssue


class EditPlanner:
    def build(self, task: IssueTask, parsed: ParsedIssue, attempt_id: str, candidate_files: list[str], test_targets: list[str]) -> EditPlan:
        hypotheses: list[str] = []
        if parsed.replace_text and parsed.with_text:
            hypotheses.append('literal replacement from issue body')
        if parsed.regex_pattern and parsed.with_text:
            hypotheses.append('regex replacement from issue body')
        if parsed.insert_before and parsed.with_text:
            hypotheses.append('insert content before anchor')
        if parsed.insert_after and parsed.with_text:
            hypotheses.append('insert content after anchor')
        if parsed.append_text:
            hypotheses.append('append text to target file')
        if parsed.target_function and parsed.with_text:
            hypotheses.append(f'function-scoped return rewrite in {parsed.target_function}')
        if parsed.add_test_file and parsed.add_test_content:
            hypotheses.append(f'append test content into {parsed.add_test_file}')
        if not hypotheses:
            hypotheses.append('no executable edit hypothesis')
        stop_after = parsed.max_attempts if parsed.max_attempts is not None else 2
        stop_after = max(1, min(stop_after, 5))
        return EditPlan(
            task_id=task.task_id,
            attempt_id=attempt_id,
            candidate_files=candidate_files,
            hypotheses=hypotheses,
            test_targets=test_targets,
            stop_after_n_failed_attempts=stop_after,
        )
