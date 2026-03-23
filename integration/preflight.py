"""Preflight dependency checker.

Call check_retrieval(), check_worker(), or check_all() at service startup
to fail fast with a clear error instead of a cryptic ImportError later.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path


def _load_system_config() -> dict:
    """Load configs/system.yaml if present; return empty dict on failure."""
    try:
        import yaml  # type: ignore[import]
        cfg_path = Path(__file__).resolve().parents[2] / "configs" / "system.yaml"
        if cfg_path.exists():
            with cfg_path.open() as fh:
                return yaml.safe_load(fh) or {}
    except Exception:
        pass
    return {}


def _service_enabled(section: str, key: str, default: bool = True) -> bool:
    cfg = _load_system_config()
    try:
        return bool(cfg[section][key]["enabled"])
    except (KeyError, TypeError):
        return default


# ── Individual checkers ───────────────────────────────────────────────────────

def check_retrieval() -> None:
    """Check retrieval broker dependencies (cocoindex).

    Only enforced when retrieval.enabled=true in configs/system.yaml.
    """
    if not _service_enabled("retrieval", "enabled"):
        return

    missing: list[str] = []
    try:
        import cocoindex  # noqa: F401
    except Exception:
        missing.append("cocoindex  →  pip install -e third_party/cocoindex-code")

    if missing:
        raise RuntimeError(
            "Missing retrieval dependencies. Run scripts/bootstrap_all.sh\n  "
            + "\n  ".join(missing)
        )


def check_aider_worker() -> None:
    """Check aider worker dependencies.

    Only enforced when workers.aider.enabled=true in configs/system.yaml.
    """
    if not _service_enabled("workers", "aider"):
        return

    missing: list[str] = []
    try:
        import aider  # noqa: F401
    except Exception:
        missing.append("aider  →  pip install -e third_party/aider")

    if missing:
        raise RuntimeError(
            "Missing aider worker dependencies. Run scripts/bootstrap_all.sh\n  "
            + "\n  ".join(missing)
        )


def check_hardened_worker() -> None:
    """Check hardened worker dependencies (code-agent-runtime).

    Only enforced when workers.hardened.enabled=true in configs/system.yaml.
    """
    if not _service_enabled("workers", "hardened"):
        return

    code_agent_path = os.environ.get("CODE_AGENT_REPO_PATH", "").strip()
    if not code_agent_path:
        raise RuntimeError(
            "CODE_AGENT_REPO_PATH is not set. "
            "Run scripts/bootstrap_all.sh or set the variable manually."
        )

    if not Path(code_agent_path).exists():
        raise RuntimeError(
            f"CODE_AGENT_REPO_PATH={code_agent_path!r} does not exist. "
            "Run scripts/materialize_repos.sh first."
        )

    if str(Path(code_agent_path)) not in sys.path:
        sys.path.insert(0, str(Path(code_agent_path)))

    missing: list[str] = []
    try:
        from apps.planner_worker import PlannerWorker  # noqa: F401
    except Exception:
        missing.append(
            "code-agent-runtime  →  pip install -e third_party/code-agent-runtime"
        )

    if missing:
        raise RuntimeError(
            "Missing hardened worker dependencies. Run scripts/bootstrap_all.sh\n  "
            + "\n  ".join(missing)
        )


def check_all() -> None:
    """Check all service dependencies in one call."""
    check_retrieval()
    check_aider_worker()
    check_hardened_worker()
