from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

from runtime.common.config import SandboxConfig


@dataclass(frozen=True)
class SandboxImageDecision:
    language: str
    image: str
    reason: str


class LanguageProfileError(RuntimeError):
    pass


class SandboxImagePolicy:
    def __init__(self, profile_root: Path):
        self.profile_root = profile_root
        self._profiles = self._load_profiles(profile_root)

    def _load_profiles(self, profile_root: Path) -> dict[str, dict]:
        if not profile_root.exists():
            raise LanguageProfileError(f'language profile root not found: {profile_root}')
        profiles: dict[str, dict] = {}
        for path in sorted(profile_root.glob('*.yaml')):
            payload = yaml.safe_load(path.read_text(encoding='utf-8')) or {}
            language = payload.get('language', path.stem)
            profiles[language] = payload
        if not profiles:
            raise LanguageProfileError(f'no language profiles found under: {profile_root}')
        return profiles

    def detect_language(self, repo_root: Path) -> str:
        scored: list[tuple[int, str]] = []
        for language, profile in self._profiles.items():
            score = 0
            for marker in profile.get('markers', []):
                if (repo_root / marker).exists():
                    score += int(profile.get('marker_weight', 5))
            for pattern in profile.get('globs', []):
                score += len(list(repo_root.glob(pattern)))
            if score:
                scored.append((score, language))
        if not scored:
            return 'python'
        scored.sort(reverse=True)
        return scored[0][1]

    def choose(self, repo_root: Path, config: SandboxConfig) -> SandboxImageDecision:
        if config.force_image:
            return SandboxImageDecision('forced', config.image, 'forced by SANDBOX_DOCKER_IMAGE + SANDBOX_FORCE_IMAGE')
        language = self.detect_language(repo_root)
        profile = self._profiles.get(language)
        if not profile:
            return SandboxImageDecision('python', config.image, 'fallback image because no profile matched')
        image = profile.get('image', config.image)
        reason = f"selected from {language} language profile"
        return SandboxImageDecision(language, image, reason)
