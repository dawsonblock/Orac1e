from __future__ import annotations

from pathlib import Path

from runtime.common.result import Result
from runtime.profile.repo_profile import RepoProfileLoader
from runtime.sandbox.base import CommandRunner
from runtime.sandbox.local_runner import LocalCommandRunner
from runtime.validation.command_discovery import CommandDiscovery
from runtime.validation.flaky_retry import FlakyRetryPolicy


class TargetedTestRunner:
    def __init__(self, runner: CommandRunner | None = None, timeout_seconds: int = 120, discovery: CommandDiscovery | None = None, profile_loader: RepoProfileLoader | None = None):
        self.runner = runner or LocalCommandRunner()
        self.timeout_seconds = timeout_seconds
        self.discovery = discovery or CommandDiscovery(profile_loader=profile_loader)
        self.profile_loader = profile_loader or RepoProfileLoader()
        self.retry_policy = FlakyRetryPolicy()

    def _run_with_optional_retry(self, repo_root: Path, cmd: list[str], *, env: dict[str, str] | None = None, failure_code: str = 'tests_failed') -> Result:
        profile = self.profile_loader.load(repo_root)
        result = self.runner.run(cmd, cwd=repo_root, env=env, timeout_seconds=self.timeout_seconds)
        if result.returncode == 0:
            return Result(True, 'ok', result.stdout)
        combined = (result.stdout + '\n' + result.stderr).strip()
        analysis = self.retry_policy.analyze(combined)
        retries_remaining = profile.flaky_retries if analysis.is_flaky_signal else 0
        while retries_remaining > 0:
            rerun = self.runner.run(cmd, cwd=repo_root, env=env, timeout_seconds=self.timeout_seconds)
            if rerun.returncode == 0:
                note = f"retried after flaky signal: {analysis.reason}" if analysis.reason else 'retried after flaky signal'
                merged = (rerun.stdout or '') + ('\n' if rerun.stdout else '') + note
                return Result(True, 'ok', merged.strip())
            combined = (rerun.stdout + '\n' + rerun.stderr).strip()
            retries_remaining -= 1
        return Result(False, failure_code, combined)

    def run_pytest(self, repo_root: Path, tests: list[str]) -> Result:
        if not tests:
            return Result(False, 'no_tests', 'no targeted tests available')
        cmd = [*self.discovery.discover(repo_root, 'python').targeted_test_prefix, *tests]
        env = {'PYTHONDONTWRITEBYTECODE': '1'}
        return self._run_with_optional_retry(repo_root, cmd, env=env, failure_code='pytest_failed')

    def run_js_ts(self, repo_root: Path, tests: list[str]) -> Result:
        cmd = list(self.discovery.discover(repo_root, 'js_ts').targeted_test_prefix)
        if tests:
            cmd.extend(tests)
        return self._run_with_optional_retry(repo_root, cmd, failure_code='js_test_failed')

    def run_rust(self, repo_root: Path, tests: list[str]) -> Result:
        cmd = list(self.discovery.discover(repo_root, 'rust').targeted_test_prefix)
        if tests:
            first = tests[0]
            cmd.extend(['--test', first])
        return self._run_with_optional_retry(repo_root, cmd, failure_code='cargo_test_failed')

    def run_for_language(self, repo_root: Path, tests: list[str], language: str) -> Result:
        if language == 'js_ts':
            return self.run_js_ts(repo_root, tests)
        if language == 'rust':
            return self.run_rust(repo_root, tests)
        return self.run_pytest(repo_root, tests)
