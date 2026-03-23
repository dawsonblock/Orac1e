"""Worker execution entry point that delegates to the main pipeline."""

from typing import Dict, Any
from integration.pipeline import run_pipeline


def run_task(task: str, repo: str) -> Dict[str, Any]:
    """
    Execute a coding task using the main execution pipeline.

    Args:
        task: Description of the coding task
        repo: Path to repository root

    Returns:
        Pipeline result dict with status and attempts
    """
    return run_pipeline(task, repo)
