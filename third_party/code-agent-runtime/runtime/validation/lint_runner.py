from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from runtime.common.result import Result
from runtime.sandbox.base import CommandRunner
from runtime.sandbox.local_runner import LocalCommandRunner

if TYPE_CHECKING:
    from runtime.validation.validation_cache import ValidationCache


class LintRunner:
    def __init__(
        self,
        runner: CommandRunner | None = None,
        timeout_seconds: int = 60,
        cache: ValidationCache | None = None
    ):
        self.runner = runner or LocalCommandRunner()
        self.timeout_seconds = timeout_seconds
        self._cache = cache

    def run_python_syntax(self, repo_root: Path, changed_files: list[str]) -> Result:
        py_files = [str(repo_root / p) for p in changed_files if p.endswith('.py')]
        if not py_files:
            return Result(True, 'ok', 'no python files changed')
        cmd = ['python', '-m', 'py_compile', *py_files]
        result = self.runner.run(cmd, cwd=repo_root, timeout_seconds=self.timeout_seconds)
        if result.returncode == 0:
            return Result(True, 'ok', result.stdout.strip())
        return Result(False, 'syntax_failed', (result.stdout + '\n' + result.stderr).strip())

    def run_js_ts_syntax(self, repo_root: Path, changed_files: list[str]) -> Result:
        js_files = [p for p in changed_files if p.endswith(('.js', '.jsx', '.mjs', '.cjs'))]
        ts_files = [p for p in changed_files if p.endswith(('.ts', '.tsx'))]
        if not js_files and not ts_files:
            return Result(True, 'ok', 'no js/ts files changed')
        if js_files:
            cmd = ['node', '--check', *js_files]
            result = self.runner.run(cmd, cwd=repo_root, timeout_seconds=self.timeout_seconds)
            if result.returncode != 0:
                return Result(False, 'syntax_failed', (result.stdout + '\n' + result.stderr).strip())
        if ts_files and (repo_root / 'tsconfig.json').exists():
            cmd = ['npx', 'tsc', '--noEmit', '--pretty', 'false']
            result = self.runner.run(cmd, cwd=repo_root, timeout_seconds=self.timeout_seconds)
            if result.returncode != 0:
                return Result(False, 'typecheck_failed', (result.stdout + '\n' + result.stderr).strip())
        return Result(True, 'ok', 'js/ts syntax checks passed')

    def run_rust_checks(self, repo_root: Path, changed_files: list[str]) -> Result:
        rs_files = [p for p in changed_files if p.endswith('.rs')]
        if not rs_files:
            return Result(True, 'ok', 'no rust files changed')
        cmd = ['cargo', 'check', '--quiet']
        result = self.runner.run(cmd, cwd=repo_root, timeout_seconds=self.timeout_seconds)
        if result.returncode == 0:
            return Result(True, 'ok', result.stdout.strip())
        return Result(False, 'cargo_check_failed', (result.stdout + '\n' + result.stderr).strip())

    def run_for_language(self, repo_root: Path, changed_files: list[str], language: str) -> Result:
        # Check cache first
        if self._cache is not None:
            cached_result = self._cache.get_lint(repo_root, changed_files, language)
            if cached_result is not None:
                return cached_result
        
        # Run lint based on language
        if language == 'js_ts':
            result = self.run_js_ts_syntax(repo_root, changed_files)
        elif language == 'rust':
            result = self.run_rust_checks(repo_root, changed_files)
        else:
            result = self.run_python_syntax(repo_root, changed_files)
        
        # Cache the result
        if self._cache is not None:
            self._cache.set_lint(repo_root, changed_files, language, result)
        
        return result
