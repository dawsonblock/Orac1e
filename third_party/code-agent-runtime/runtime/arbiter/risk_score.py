from __future__ import annotations

from runtime.events.schemas import PatchArtifact


class RiskScorer:
    SENSITIVE_HINTS = ('auth', 'security', 'secret', 'token', 'credential', 'permission', 'runtime', 'core', 'parser', 'serialize', 'migrate')

    def _touches_sensitive_paths(self, patch: PatchArtifact) -> bool:
        for rel in patch.changed_files:
            lowered = rel.lower()
            if any(hint in lowered for hint in self.SENSITIVE_HINTS):
                return True
        return False

    def score(self, patch: PatchArtifact, preflight_ok: bool, lint_ok: bool, tests_ok: bool, *, full_tests_ok: bool | None = None, added_test_count: int = 0) -> float:
        risk = 0.15
        risk += 0.05 * max(0, len(patch.changed_files) - 1)
        if self._touches_sensitive_paths(patch):
            risk += 0.10
        if not preflight_ok:
            risk += 0.30
        if not lint_ok:
            risk += 0.25
        if not tests_ok:
            risk += 0.35
        if full_tests_ok is False:
            risk += 0.10
        elif full_tests_ok is True:
            risk -= 0.03
        if added_test_count:
            risk -= min(0.06, 0.02 * added_test_count)
        return max(0.0, min(1.0, risk))

    def confidence(self, risk_score: float) -> float:
        return max(0.0, round(1.0 - risk_score, 3))
