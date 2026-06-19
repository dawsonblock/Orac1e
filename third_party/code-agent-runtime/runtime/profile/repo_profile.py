from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import fnmatch
import tomllib
from typing import Any

import yaml


@dataclass(frozen=True)
class LanguageCommandProfile:
    lint: list[str] | None = None
    targeted_test_prefix: list[str] | None = None
    full_test: list[str] | None = None
    package_manager: str | None = None


@dataclass(frozen=True)
class RepoProfile:
    ignore_paths: list[str] = field(default_factory=list)
    test_paths: list[str] = field(default_factory=list)
    sensitive_paths: list[str] = field(default_factory=list)
    flaky_retries: int = 0
    max_files: int | None = None
    max_attempts: int | None = None
    python: LanguageCommandProfile = field(default_factory=LanguageCommandProfile)
    js_ts: LanguageCommandProfile = field(default_factory=LanguageCommandProfile)
    rust: LanguageCommandProfile = field(default_factory=LanguageCommandProfile)

    def is_ignored(self, relpath: str) -> bool:
        return any(_match_path(relpath, pattern) for pattern in self.ignore_paths)

    def is_sensitive(self, relpath: str) -> bool:
        return any(_match_path(relpath, pattern) for pattern in self.sensitive_paths)


def _coerce_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, (list, tuple)):
        out: list[str] = []
        for item in value:
            if item is None:
                continue
            text = str(item).strip()
            if text:
                out.append(text)
        return out
    return [str(value).strip()]


def _normalize_mapping(payload: dict[str, Any] | None) -> dict[str, Any]:
    return payload or {}


def _lang_profile(raw: dict[str, Any] | None) -> LanguageCommandProfile:
    raw = _normalize_mapping(raw)
    return LanguageCommandProfile(
        lint=_coerce_list(raw.get('lint')) or None,
        targeted_test_prefix=_coerce_list(raw.get('targeted_test_prefix')) or None,
        full_test=_coerce_list(raw.get('full_test')) or None,
        package_manager=(str(raw.get('package_manager')).strip() if raw.get('package_manager') else None),
    )


def _match_path(relpath: str, pattern: str) -> bool:
    rel = relpath.replace('\\', '/').lstrip('./')
    pat = pattern.replace('\\', '/').lstrip('./')
    if fnmatch.fnmatch(rel, pat):
        return True
    if pat.endswith('/') and rel.startswith(pat):
        return True
    if '/' not in pat and rel.startswith(pat.rstrip('/') + '/'):
        return True
    return False


class RepoProfileLoader:
    def load(self, repo_root: Path) -> RepoProfile:
        root = Path(repo_root)
        merged: dict[str, Any] = {}

        pyproject = root / 'pyproject.toml'
        if pyproject.exists():
            with pyproject.open('rb') as fh:
                payload = tomllib.load(fh)
            tool = payload.get('tool', {})
            profile = tool.get('code_agent_runtime') or tool.get('code-agent-runtime')
            if isinstance(profile, dict):
                merged = _deep_merge(merged, profile)

        for candidate in [root / '.agent-runtime.yaml', root / '.agent-runtime.yml', root / '.agent' / 'runtime.yaml', root / '.agent' / 'runtime.yml']:
            if candidate.exists():
                with candidate.open('r', encoding='utf-8') as fh:
                    payload = yaml.safe_load(fh) or {}
                if isinstance(payload, dict):
                    merged = _deep_merge(merged, payload)

        return RepoProfile(
            ignore_paths=_coerce_list(merged.get('ignore_paths')),
            test_paths=_coerce_list(merged.get('test_paths')),
            sensitive_paths=_coerce_list(merged.get('sensitive_paths')),
            flaky_retries=max(0, int(merged.get('flaky_retries', 0) or 0)),
            max_files=(int(merged['max_files']) if merged.get('max_files') is not None else None),
            max_attempts=(int(merged['max_attempts']) if merged.get('max_attempts') is not None else None),
            python=_lang_profile(merged.get('python')),
            js_ts=_lang_profile(merged.get('js_ts')),
            rust=_lang_profile(merged.get('rust')),
        )


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    out = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _deep_merge(out[key], value)
        else:
            out[key] = value
    return out
