"""Validation module for running tests and capturing output."""

import logging
import subprocess
from pathlib import Path
from typing import Tuple

logger = logging.getLogger(__name__)


def run_tests(repo: str) -> Tuple[bool, str]:
    """
    Run tests in the repository and capture output.

    Args:
        repo: Path to repository root

    Returns:
        Tuple of (success_boolean, combined_output_string)
    """
    repo_path = Path(repo)

    try:
        result = subprocess.run(
            ["python", "-m", "pytest", "-q"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=120
        )
        output = result.stdout + result.stderr
        success = result.returncode == 0
    except subprocess.TimeoutExpired as e:
        logger.error(f"Tests timed out after 120s: {e}")
        output = f"TIMEOUT: Tests did not complete within 120 seconds\n{e.stdout or ''}\n{e.stderr or ''}"
        success = False
    except Exception as e:
        logger.error(f"Failed to run tests: {e}")
        output = f"ERROR: Failed to run tests: {e}"
        success = False

    return success, output


def validate(repo: str) -> bool:
    """
    Simple validation wrapper that only returns success status.

    Args:
        repo: Path to repository root

    Returns:
        True if tests pass, False otherwise
    """
    success, _ = run_tests(repo)
    return success
