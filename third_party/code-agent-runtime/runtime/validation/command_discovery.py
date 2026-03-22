from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from runtime.profile.repo_profile import RepoProfileLoader


@dataclass(frozen=True)
class RepoCommands:
    language: str
    lint: list[str]
    targeted_test_prefix: list[str]
    full_test: list[str]
    package_manager: str | None = None


class CommandDiscovery:
    def __init__(self, profile_loader: RepoProfileLoader | None = None):
        self.profile_loader = profile_loader or RepoProfileLoader()

    def detect_language(self, repo_root: Path) -> str:
        if (repo_root / 'Cargo.toml').exists():
            return 'rust'
        if (repo_root / 'package.json').exists():
            return 'js_ts'
        return 'python'

    def discover(self, repo_root: Path, language: str | None = None) -> RepoCommands:
        lang = language or self.detect_language(repo_root)
        profile = self.profile_loader.load(repo_root)
        if lang == 'rust':
            default = RepoCommands(language='rust', lint=['cargo', 'check', '--quiet'], targeted_test_prefix=['cargo', 'test', '--quiet'], full_test=['cargo', 'test', '--quiet'], package_manager='cargo')
            override = profile.rust
            return RepoCommands(
                language='rust',
                lint=override.lint or default.lint,
                targeted_test_prefix=override.targeted_test_prefix or default.targeted_test_prefix,
                full_test=override.full_test or default.full_test,
                package_manager=override.package_manager or default.package_manager,
            )
        if lang == 'js_ts':
            if (repo_root / 'pnpm-lock.yaml').exists():
                pm = 'pnpm'
            elif (repo_root / 'yarn.lock').exists():
                pm = 'yarn'
            else:
                pm = 'npm'
            lint = ['npx', 'tsc', '--noEmit', '--pretty', 'false'] if (repo_root / 'tsconfig.json').exists() else ['node', '--check']
            if pm == 'npm':
                targeted = ['npm', 'test', '--']
                full = ['npm', 'test']
            else:
                targeted = [pm, 'test']
                full = [pm, 'test']
            default = RepoCommands(language='js_ts', lint=lint, targeted_test_prefix=targeted, full_test=full, package_manager=pm)
            override = profile.js_ts
            return RepoCommands(
                language='js_ts',
                lint=override.lint or default.lint,
                targeted_test_prefix=override.targeted_test_prefix or default.targeted_test_prefix,
                full_test=override.full_test or default.full_test,
                package_manager=override.package_manager or default.package_manager,
            )
        default = RepoCommands(language='python', lint=['python', '-m', 'py_compile'], targeted_test_prefix=['python', '-m', 'pytest'], full_test=['python', '-m', 'pytest'], package_manager=None)
        override = profile.python
        return RepoCommands(
            language='python',
            lint=override.lint or default.lint,
            targeted_test_prefix=override.targeted_test_prefix or default.targeted_test_prefix,
            full_test=override.full_test or default.full_test,
            package_manager=override.package_manager or default.package_manager,
        )
