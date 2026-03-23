import logging
from typing import Dict, Any
from integration.worker_hardened.bridge import run_hardened
from integration.shared_py.models import ProposeRequest

logger = logging.getLogger(__name__)


def coding_planner_execute(task: str, repo_path: str) -> Dict[str, Any]:
    """
    Supervised Coding Planner that acts as a reliability layer.

    1. Attempts hardened/deterministic fix logic for known patterns.
    2. Returns a standardized proposal block.
    """
    logger.info(f"Planner starting execution for task: {task}")

    # Enforce P0 #3: Use ProposeRequest for internal normalization
    from integration.shared_py.models import ProposeContext, Constraints
    req = ProposeRequest(
        run_id="planner_run",
        repo_name="default",
        repo_path=repo_path,
        task=task,
        mode="autonomous",
        context=ProposeContext(),
        constraints=Constraints()
    )

    # 1. Execute hardened worker (bridge to heuristic + autonomous paths)
    # The run_hardened function now includes the P0 #3.C AST-based fallback
    # for the first_token bug.
    try:
        # Note: run_hardened requires CODE_AGENT_REPO_PATH in env
        import os
        if "CODE_AGENT_REPO_PATH" not in os.environ:
            rt_path = "third_party/code-agent-runtime"
            os.environ["CODE_AGENT_REPO_PATH"] = os.path.abspath(rt_path)

        result = run_hardened(req)
    except Exception as e:
        logger.error(f"Worker execution failed: {e}")
        return {
            "success": False,
            "error": "WORKER_FATAL",
            "reason": str(e)
        }

    # 2. Reject Empty Plans (P0 #3.B)
    # The hardened worker returns a dict from to_response
    if not isinstance(result, dict) or not result.get("patch"):
        logger.warning("Hardened worker produced no patch. Rejecting plan.")
        return {
            "success": False,
            "error": "PLANNER_FAILURE",
            "reason": "Task requires reasoning beyond current scaffold"
        }

    # 3. Enforce structured patch output (P0 #3.A)
    # Mapping from worker's response format (which uses 'patch')
    proposal = {
        "success": True,
        "file": result.get("file"),
        "search": result.get("search"),
        "replace": result.get("replace"),
        "confidence": result.get("confidence", 0.9),
        "patch": result.get("patch")
    }

    logger.info(f"Planner finished with proposal for {proposal.get('file')}")
    return proposal
