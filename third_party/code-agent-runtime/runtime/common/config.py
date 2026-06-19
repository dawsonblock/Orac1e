from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


@dataclass(frozen=True)
class RuntimePaths:
    state_root: Path
    cache_root: Path
    workspaces_root: Path
    outbox_root: Path

    @classmethod
    def under(cls, root: Path) -> "RuntimePaths":
        return cls(
            state_root=root,
            cache_root=root / "repo-cache",
            workspaces_root=root / "workspaces",
            outbox_root=root / ".agent_outbox",
        )


@dataclass(frozen=True)
class SandboxConfig:
    mode: Literal["local", "docker"] = "local"
    image: str = "python:3.11-slim"
    timeout_seconds: int = 120
    network: str = "none"
    memory_limit: str = "2g"
    cpu_limit: str = "1.0"
    pull_policy: Literal["always", "missing", "never"] = "never"
    mount_repo_readwrite: bool = True
    detect_language: bool = True
    image_policy_root: Path = Path('domains/code/language_profiles')
    force_image: bool = False

    @classmethod
    def from_env(cls) -> "SandboxConfig":
        explicit_image = os.getenv("SANDBOX_DOCKER_IMAGE")
        return cls(
            mode=os.getenv("SANDBOX_MODE", "local"),
            image=explicit_image or "python:3.11-slim",
            timeout_seconds=int(os.getenv("SANDBOX_TIMEOUT_SECONDS", "120")),
            network=os.getenv("SANDBOX_NETWORK", "none"),
            memory_limit=os.getenv("SANDBOX_MEMORY_LIMIT", "2g"),
            cpu_limit=os.getenv("SANDBOX_CPU_LIMIT", "1.0"),
            pull_policy=os.getenv("SANDBOX_DOCKER_PULL", "never"),
            mount_repo_readwrite=os.getenv("SANDBOX_MOUNT_REPO_READWRITE", "true").lower() == "true",
            detect_language=os.getenv("SANDBOX_DETECT_LANGUAGE", "true").lower() == "true",
            image_policy_root=Path(os.getenv("SANDBOX_IMAGE_POLICY_ROOT", "domains/code/language_profiles")),
            force_image=bool(explicit_image) and os.getenv("SANDBOX_FORCE_IMAGE", "false").lower() == 'true',
        )


@dataclass(frozen=True)
class GitHubAppConfig:
    app_id: str
    private_key_path: Path
    installation_id: int
    api_url: str = "https://api.github.com"
    dry_run: bool = True

    @classmethod
    def from_env(cls) -> "GitHubAppConfig":
        app_id = os.getenv("GITHUB_APP_ID", "")
        key_path = Path(os.getenv("GITHUB_APP_PRIVATE_KEY_PATH", ""))
        installation_id = int(os.getenv("GITHUB_INSTALLATION_ID", "0"))
        api_url = os.getenv("GITHUB_API_URL", "https://api.github.com")
        dry_run = os.getenv("GITHUB_DRY_RUN", "true").lower() == "true"
        return cls(
            app_id=app_id,
            private_key_path=key_path,
            installation_id=installation_id,
            api_url=api_url,
            dry_run=dry_run,
        )


@dataclass(frozen=True)
class ValidationConfig:
    """Adaptive timeout configuration for validation stages.

    Timeouts scale based on patch size to prevent premature timeouts
    on large changes while keeping reasonable defaults for small patches.
    """
    lint_timeout: int = 60
    targeted_tests_timeout: int = 120
    full_tests_timeout: int = 300
    preflight_timeout: int = 30

    @classmethod
    def from_patch_size(cls, file_count: int, base_timeout: int = 120) -> "ValidationConfig":
        """Create ValidationConfig with timeouts scaled to patch size.

        Args:
            file_count: Number of files in the patch
            base_timeout: Base timeout in seconds (default: 120)

        Returns:
            ValidationConfig with adaptive timeouts
        """
        # Scale factor: 1.0 for small patches, up to 2.0 for large patches
        scale_factor = min(max(file_count / 10, 1.0), 2.0)

        return cls(
            lint_timeout=int(60 * scale_factor),
            targeted_tests_timeout=int(base_timeout * scale_factor),
            full_tests_timeout=int(300 * scale_factor),
            preflight_timeout=int(30 * scale_factor),
        )

    @classmethod
    def from_env(cls) -> "ValidationConfig":
        """Create ValidationConfig from environment variables."""
        return cls(
            lint_timeout=int(os.getenv("VALIDATION_LINT_TIMEOUT", "60")),
            targeted_tests_timeout=int(os.getenv("VALIDATION_TESTS_TIMEOUT", "120")),
            full_tests_timeout=int(os.getenv("VALIDATION_FULL_TESTS_TIMEOUT", "300")),
            preflight_timeout=int(os.getenv("VALIDATION_PREFLIGHT_TIMEOUT", "30")),
        )
