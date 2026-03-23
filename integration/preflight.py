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
            import cocoindex_code
        except Exception:
            missing.append("cocoindex-code")

    if missing:
        raise RuntimeError(f"Missing dependencies: {missing}. Run scripts/bootstrap_all.sh")

def check_all():
    """Compatibility wrapper for legacy calls (from bootstrap or service startup)."""
    check()


if __name__ == "__main__":
    check()
