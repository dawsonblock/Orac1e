from __future__ import annotations

from runtime.events.schemas import EditPlan


class StopConditions:
    def should_stop(self, plan: EditPlan) -> tuple[bool, str]:
        if not plan.candidate_files:
            return True, "no candidate files"
        if "no executable edit hypothesis" in plan.hypotheses:
            return True, "no executable edit hypothesis"
        return False, "ok"
