from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class RepoLanguage:
    primary: str
    reason: str


class RepoLanguageDetector:
    """Cheap repo-language detector for validation and test command selection."""

    def detect(self, repo_root: Path) -> RepoLanguage:
        if (repo_root / 'Cargo.toml').exists():
            return RepoLanguage('rust', 'Cargo.toml present')
        if (repo_root / 'package.json').exists() or (repo_root / 'pnpm-lock.yaml').exists() or (repo_root / 'yarn.lock').exists():
            ts_count = len(list(repo_root.rglob('*.ts'))) + len(list(repo_root.rglob('*.tsx')))
            js_count = len(list(repo_root.rglob('*.js'))) + len(list(repo_root.rglob('*.jsx')))
            kind = 'js_ts' if ts_count or js_count else 'js_ts'
            return RepoLanguage(kind, 'package.json or JS/TS lockfile present')
        py_count = len(list(repo_root.rglob('*.py')))
        if (repo_root / 'pyproject.toml').exists() or (repo_root / 'requirements.txt').exists() or py_count:
            return RepoLanguage('python', 'Python markers present')
        return RepoLanguage('python', 'fallback default')
