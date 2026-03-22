from __future__ import annotations

from runtime.events.schemas import PublishDecision, ValidationReport


class DecisionGate:
    def decide(self, report: ValidationReport, patch_has_tests: bool) -> PublishDecision:
        if not report.preflight_passed:
            return PublishDecision(report.task_id, report.attempt_id, 'reject', 'patch preflight failed')
        if not report.targeted_tests_passed:
            return PublishDecision(report.task_id, report.attempt_id, 'comment_only', 'targeted validation failed')
        if report.confidence < 0.60:
            return PublishDecision(report.task_id, report.attempt_id, 'comment_only', 'confidence too low')
        if report.confidence < 0.82 or not patch_has_tests:
            return PublishDecision(report.task_id, report.attempt_id, 'draft_pr', 'needs review')
        return PublishDecision(report.task_id, report.attempt_id, 'pr', 'validation passed')
