from __future__ import annotations

from pathlib import Path

from runtime.common.result import Result
from runtime.profile.repo_profile import RepoProfileLoader
from runtime.sandbox.base import CommandRunner
from runtime.sandbox.local_runner import LocalCommandRunner
from runtime.validation.command_discovery import CommandDiscovery
from runtime.validation.flaky_retry import FlakyRetryPolicy


class FullTestRunner:
    def __init__(self, runner: CommandRunner | None = None, timeout_seconds: int = 300, discovery: CommandDiscovery | None = None, profile_loader: RepoProfileLoader | None = None):
        self.runner = runner or LocalCommandRunner()
        self.timeout_seconds = timeout_seconds
        self.profile_loader = profile_loader or RepoProfileLoader()
        self.discovery = discovery or CommandDiscovery(profile_loader=self.profile_loader)
        self.retry_policy = FlakyRetryPolicy()

    def run_for_language(self, repo_root: Path, language: str) -> Result:
        cmd = self.discovery.discover(repo_root, language).full_test
        result = self.runner.run(cmd, cwd=repo_root, timeout_seconds=self.timeout_seconds)
        if result.returncode == 0:
            return Result(True, 'ok', result.stdout)
        combined = (result.stdout + '\n' + result.stderr).strip()
        analysis = self.retry_policy.analyze(combined)
        retries_remaining = self.profile_loader.load(repo_root).flaky_retries if analysis.is_flaky_signal else 0
        while retries_remaining > 0:
            rerun = self.runner.run(cmd, cwd=repo_root, timeout_seconds=self.timeout_seconds)
            if rerun.returncode == 0:
                note = f"retried full suite after flaky signal: {analysis.reason}" if analysis.reason else 'retried full suite after flaky signal'
                merged = (rerun.stdout or '') + ('\n' if rerun.stdout else '') + note
                return Result(True, 'ok', merged.strip())
            combined = (rerun.stdout + '\n' + rerun.stderr).strip()
            retries_remaining -= 1
        return Result(False, 'full_tests_failed', combined)
