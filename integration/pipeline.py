"""Main execution pipeline with retry loop and test feedback."""

import logging
from typing import Dict, Any, Optional

from integration.context_builder import build_context
from integration.llm_planner import create_plan
from integration.failure_analyzer import analyze_failure
from integration.patch_executor import apply_plan
from integration.validation import run_tests

logger = logging.getLogger(__name__)

MAX_ATTEMPTS = 4


def run_pipeline(task: str, repo: str) -> Dict[str, Any]:
    """
    Execute the full pipeline: task → context → plan → patch → test → loop.

    Args:
        task: Description of the coding task
        repo: Path to repository root

    Returns:
        Dict with 'status' (applied/failed) and 'attempts' count
    """
    logger.info(f"Starting pipeline for task: {task}")

    current_plan: Optional[Dict[str, Any]] = None

    for attempt in range(MAX_ATTEMPTS):
        logger.info(f"Attempt {attempt + 1}/{MAX_ATTEMPTS}")

        # Build fresh context on each attempt to reflect current file state
        context = build_context(repo)
        logger.info(f"Built context with {len(context)} items")

        # Get plan (initial or from failure analysis)
        if current_plan is None:
            current_plan = create_plan(task, context)

        if not current_plan or not current_plan.get("edits"):
            logger.warning("No plan produced, will retry")
            current_plan = None
            continue

        # Apply the plan
        result = apply_plan(current_plan, repo)

        if not result.get("success"):
            logger.warning(f"Patch application failed: {result.get('error')}")
            # Try again with fresh plan
            current_plan = None
            continue

        logger.info(f"Applied patches to: {result.get('files', [])}")

        # Run tests
        tests_passed, test_output = run_tests(repo)

        if tests_passed:
            logger.info(f"Tests passed after {attempt + 1} attempts")
            return {
                "status": "applied",
                "attempts": attempt + 1,
                "files_changed": result.get("files", [])
            }

        # Tests failed - analyze and replan with fresh context
        logger.info("Tests failed, analyzing failure output")
        current_plan = analyze_failure(task, test_output, context)

        if not current_plan:
            logger.warning("Failure analysis did not produce new plan")
            current_plan = None

    # Max attempts reached without success
    logger.error(f"Failed after {MAX_ATTEMPTS} attempts")
    return {
        "status": "failed",
        "attempts": MAX_ATTEMPTS,
        "error": "Max attempts reached without passing tests"
    }
