import yaml
from pathlib import Path

def load_config():
    """Load configs/system.yaml if present."""
    cfg_path = Path(__file__).resolve().parents[1] / "configs" / "system.yaml"
    with open(cfg_path) as f:
        return yaml.safe_load(f)

def check():
    """Check dependencies based on active services in system.yaml."""
    cfg = load_config()
    missing = []

    if cfg.get("workers", {}).get("aider", {}).get("enabled", False):
        try:
            import aider
        except Exception:
            missing.append("aider")

    if cfg.get("workers", {}).get("hardened", {}).get("enabled", False):
        try:
            from apps.planner_worker import PlannerWorker
        except Exception:
            missing.append("code-agent-runtime")

    if cfg.get("retrieval", {}).get("broker", {}).get("enabled", False):
        try:
            import cocoindex
        except Exception:
            missing.append("cocoindex")

    if missing:
        raise RuntimeError(f"Missing dependencies: {missing}. Run scripts/bootstrap_all.sh")

def check_all():
    """Compatibility wrapper for legacy calls (from bootstrap or service startup)."""
    check()


# Specific check functions for individual services
def check_retrieval():
    """Check retrieval broker dependencies."""
    cfg = load_config()
    if cfg.get("retrieval", {}).get("broker", {}).get("enabled", True):
        try:
            import cocoindex
        except Exception as exc:
            raise RuntimeError(f"cocoindex not available: {exc}")

def check_aider_worker():
    """Check aider worker dependencies."""
    cfg = load_config()
    if cfg.get("workers", {}).get("aider", {}).get("enabled", True):
        try:
            import aider
        except Exception as exc:
            raise RuntimeError(f"aider not available: {exc}")

def check_hardened_worker():
    """Check hardened worker dependencies."""
    cfg = load_config()
    if cfg.get("workers", {}).get("hardened", {}).get("enabled", True):
        try:
            from apps.planner_worker import PlannerWorker
        except Exception as exc:
            raise RuntimeError(f"code-agent-runtime not available: {exc}")
