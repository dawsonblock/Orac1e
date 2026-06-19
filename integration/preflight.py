"""Preflight checks for Orac1e Control Plane.

Validates that required dependencies, scripts, and configuration are present
before starting services. Exits non-zero on any hard failure.
"""

from __future__ import annotations

import sys
import warnings
from dataclasses import dataclass, field
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


@dataclass
class PreflightResult:
    ok: bool = True
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def load_config() -> dict:
    """Load configs/system.yaml if present."""
    cfg_path = ROOT / "configs" / "system.yaml"
    if not cfg_path.exists():
        raise FileNotFoundError(f"Missing config: {cfg_path}")
    with open(cfg_path) as f:
        return yaml.safe_load(f) or {}


def check() -> PreflightResult:
    """Run all preflight checks. Returns a structured result."""
    result = PreflightResult()

    # --- Python version ---
    if sys.version_info < (3, 11):
        result.errors.append(f"Python 3.11+ required, found {sys.version}")
        result.ok = False
        return result

    # --- Config file ---
    try:
        cfg = load_config()
    except FileNotFoundError as exc:
        result.errors.append(str(exc))
        result.ok = False
        return result

    # --- Required scripts ---
    required_scripts = [
        "scripts/bootstrap_all.sh",
        "scripts/smoke_test.sh",
        "scripts/run_local.sh",
        "scripts/coding_run_promotion.py",
    ]
    for script in required_scripts:
        if not (ROOT / script).exists():
            result.errors.append(f"Missing required script: {script}")
            result.ok = False

    # --- Worker dependencies ---
    if cfg.get("workers", {}).get("aider", {}).get("enabled", False):
        try:
            import aider  # noqa: F401
        except Exception:
            result.errors.append("aider not installed (worker.aider.enabled=true)")
            result.ok = False

    if cfg.get("workers", {}).get("hardened", {}).get("enabled", False):
        try:
            from runtime.common.config import SandboxConfig  # noqa: F401
        except Exception:
            result.errors.append("code-agent-runtime not installed (worker.hardened.enabled=true)")
            result.ok = False

    if cfg.get("retrieval", {}).get("broker", {}).get("enabled", False):
        try:
            import cocoindex  # noqa: F401
        except Exception:
            result.warnings.append("cocoindex not installed (retrieval.broker.enabled=true)")

    # --- Workspace layout ---
    workspace_dirs = [
        ROOT / "workspace" / "runs",
        ROOT / "workspace" / "fixtures",
    ]
    for d in workspace_dirs:
        if not d.exists():
            result.warnings.append(f"Missing workspace directory: {d.relative_to(ROOT)}")

    return result


def check_all() -> None:
    """Compatibility wrapper for legacy calls. Raises on failure."""
    result = check()
    if not result.ok:
        raise RuntimeError(f"Preflight failed: {'; '.join(result.errors)}")


def main() -> int:
    """CLI entrypoint. Returns 0 on success, nonzero on failure."""
    result = check()

    for error in result.errors:
        print(f"ERROR: {error}", file=sys.stderr)
    for warning in result.warnings:
        print(f"WARNING: {warning}", file=sys.stderr)

    if not result.ok:
        return 1

    print("preflight: ok")
    return 0


# --- Individual service checks (used by service startup) ---


def check_retrieval() -> None:
    """Check retrieval broker dependencies."""
    cfg = load_config()
    if cfg.get("retrieval", {}).get("broker", {}).get("enabled", True):
        try:
            import cocoindex  # noqa: F401
        except Exception as exc:
            raise RuntimeError(f"cocoindex not available: {exc}")


def check_aider_worker() -> None:
    """Check aider worker dependencies."""
    cfg = load_config()
    if cfg.get("workers", {}).get("aider", {}).get("enabled", True):
        try:
            import aider  # noqa: F401
        except Exception as exc:
            raise RuntimeError(f"aider not available: {exc}")


def check_hardened_worker() -> None:
    """Check hardened worker dependencies."""
    cfg = load_config()
    if cfg.get("workers", {}).get("hardened", {}).get("enabled", True):
        try:
            from runtime.common.config import SandboxConfig  # noqa: F401
        except Exception as exc:
            raise RuntimeError(f"code-agent-runtime not available: {exc}")


if __name__ == "__main__":
    raise SystemExit(main())
