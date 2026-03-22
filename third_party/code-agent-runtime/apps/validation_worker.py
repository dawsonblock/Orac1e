from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

from runtime.arbiter.risk_score import RiskScorer
from runtime.common.config import SandboxConfig
from runtime.common.result import Result
from runtime.events.schemas import EditPlan, PatchArtifact, ValidationReport
from runtime.sandbox.docker_runner import DockerCommandRunner
from runtime.sandbox.image_policy import SandboxImagePolicy
from runtime.sandbox.local_runner import LocalCommandRunner
from runtime.validation.full_tests import FullTestRunner
from runtime.validation.language_detection import RepoLanguageDetector
from runtime.validation.lint_runner import LintRunner
from runtime.validation.patch_preflight import PatchPreflight
from runtime.validation.targeted_tests import TargetedTestRunner
from runtime.validation.test_selector import TestSelector


class ValidationWorker:
    def __init__(self, sandbox: SandboxConfig | None = None):
        self.sandbox = sandbox or SandboxConfig.from_env()
        self.preflight = PatchPreflight()
        self.selector = TestSelector()
        self.risk = RiskScorer()
        self.detector = RepoLanguageDetector()

    @staticmethod
    def should_run_full_tests(patch: PatchArtifact, preflight_ok: bool, lint_ok: bool, tests_ok: bool) -> bool:
        """
        Determine if full test suite should run based on patch characteristics.
        
        Skips full tests when:
        - Any earlier stage failed
        - Patch is low-risk (docs, config, refactoring only)
        - Only low-value changes (no test/core file changes)
        """
        if not (preflight_ok and lint_ok and tests_ok):
            return False
        
        # Low-risk extension patterns (docs, config, refactoring)
        low_risk_extensions = {'.md', '.txt', '.yaml', '.yml', '.json', '.toml', '.lock'}
        
        # If all files are low-risk, skip full tests
        if all(Path(f).suffix in low_risk_extensions for f in patch.changed_files):
            return False
        
        # For small patches, check if any meaningful changes exist
        if len(patch.changed_files) <= 2:
            # Test file changes are meaningful
            has_test_changes = any(
                '_test.' in f or '_tests.' in f or f.endswith('_test.py') or f.endswith('_tests.py')
                for f in patch.changed_files
            )
            # Core source changes are meaningful
            has_core_changes = any(
                f.startswith('src/') or f.startswith('lib/') or f.startswith('core/')
                for f in patch.changed_files
            )
            # If neither test nor core files changed, skip full tests
            if not has_test_changes and not has_core_changes:
                return False
        
        return True

    def _make_runner(self, repo_root: Path):
        if self.sandbox.mode == 'docker':
            config = self.sandbox
            if config.detect_language:
                policy_root = config.image_policy_root
                if not policy_root.is_absolute():
                    policy_root = Path(__file__).resolve().parents[1] / policy_root
                decision = SandboxImagePolicy(policy_root).choose(repo_root, config)
                config = SandboxConfig(
                    mode=config.mode,
                    image=decision.image,
                    timeout_seconds=config.timeout_seconds,
                    network=config.network,
                    pull_policy=config.pull_policy,
                    mount_repo_readwrite=config.mount_repo_readwrite,
                    detect_language=config.detect_language,
                    image_policy_root=config.image_policy_root,
                    force_image=config.force_image,
                )
            runner = DockerCommandRunner(config)
            if runner.docker_available():
                return runner
            return LocalCommandRunner()
        return LocalCommandRunner()

    def run(self, repo_root: Path, plan: EditPlan, patch: PatchArtifact) -> tuple[ValidationReport, dict[str, Result]]:
        runner = self._make_runner(repo_root)
        lint = LintRunner(runner=runner, timeout_seconds=self.sandbox.timeout_seconds)
        tests_runner = TargetedTestRunner(runner=runner, timeout_seconds=self.sandbox.timeout_seconds)
        full_runner = FullTestRunner(runner=runner, timeout_seconds=min(300, self.sandbox.timeout_seconds * 2))
        language = self.detector.detect(repo_root).primary

        # Preflight must run first (validates patch structure)
        preflight = self.preflight.run(repo_root, patch)
        
        # Pre-compute test selection before parallel execution
        # This is needed to determine if full tests should run
        selected_tests = self.selector.select(repo_root, patch.changed_files, plan.test_targets)
        
        # Execute lint and targeted tests in parallel
        lint_result: Optional[Result] = None
        tests: Optional[Result] = None
        
        with ThreadPoolExecutor(max_workers=2) as executor:
            lint_future = executor.submit(
                lint.run_for_language, repo_root, patch.changed_files, language
            )
            tests_future = executor.submit(
                tests_runner.run_for_language, repo_root, selected_tests, language
            )
            
            # Collect results as they complete
            for future in as_completed([lint_future, tests_future]):
                if future is lint_future:
                    lint_result = future.result()
                elif future is tests_future:
                    tests = future.result()
        
        # Fallback for any None results (should not happen, but safety)
        if lint_result is None:
            logger.warning("Fallback triggered: lint_result was None, re-running synchronously")
            lint_result = lint.run_for_language(repo_root, patch.changed_files, language)
        if tests is None:
            logger.warning("Fallback triggered: tests was None, re-running synchronously")
            tests = tests_runner.run_for_language(repo_root, selected_tests, language)

        full_tests: Result
        # Determine if full tests should run using enhanced skip logic
        if self.should_run_full_tests(patch, preflight.ok, lint_result.ok, tests.ok):
            full_tests = full_runner.run_for_language(repo_root, language)
            full_tests_passed = full_tests.ok
        else:
            full_tests = Result(True, 'skipped', 'full tests skipped for low-risk patch')
            full_tests_passed = None

        risk_score = self.risk.score(
            patch, preflight.ok, lint_result.ok, tests.ok, full_tests_ok=full_tests_passed, added_test_count=len(patch.added_tests)
        )
        confidence = self.risk.confidence(risk_score)
        notes = [msg for msg in [preflight.message, lint_result.message, tests.message, full_tests.message] if msg]
        if selected_tests:
            notes.append('selected_tests=' + ', '.join(selected_tests))
        notes.append(f'language={language}')
        report = ValidationReport(
            task_id=plan.task_id,
            attempt_id=plan.attempt_id,
            preflight_passed=preflight.ok,
            lint_passed=lint_result.ok,
            targeted_tests_passed=tests.ok,
            full_tests_passed=full_tests_passed,
            risk_score=risk_score,
            confidence=confidence,
            changed_files=patch.changed_files,
            notes=notes,
        )
        return report, {'preflight': preflight, 'lint': lint_result, 'tests': tests, 'full_tests': full_tests}
