"""End-to-end proof: hardened worker fixes a real bug in the bundled fixture repo.

This is the canonical system-function test. It verifies the full pipeline:

  1. The buggy fixture repo has a known defect:
       src/parser.py:  def first_token(tokens): return tokens[0]
     The test suite expects first_token([]) to return None, but it raises
     IndexError instead.

  2. run_hardened() is invoked with a plain-language task description.

  3. After the worker runs, the test asserts:
     - a non-empty diff was produced
     - src/parser.py was modified
     - the fix is semantically correct (returns None for empty input)
     - the bundled test_parser.py now passes

This test requires CODE_AGENT_REPO_PATH to point to the materialized
code-agent-runtime directory (set by bootstrap_all.sh / common.sh).

Skip if CODE_AGENT_REPO_PATH is not available so CI without the runtime
still passes.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

# ── Conditional skip if runtime is not available ──────────────────────────────

_CODE_AGENT_PATH = os.environ.get("CODE_AGENT_REPO_PATH", "").strip()
_RUNTIME_AVAILABLE = bool(_CODE_AGENT_PATH) and Path(_CODE_AGENT_PATH).exists()

if _RUNTIME_AVAILABLE and _CODE_AGENT_PATH not in sys.path:
    sys.path.insert(0, _CODE_AGENT_PATH)

try:
    from apps.planner_worker import PlannerWorker  # noqa: F401
    _IMPORTS_OK = True
except Exception:
    _IMPORTS_OK = False

_SKIP_REASON = (
    "CODE_AGENT_REPO_PATH not set or code-agent-runtime not importable; "
    "run scripts/bootstrap_all.sh first"
)
requires_runtime = pytest.mark.skipif(
    not (_RUNTIME_AVAILABLE and _IMPORTS_OK),
    reason=_SKIP_REASON,
)

# ── Fixture helpers ────────────────────────────────────────────────────────────

ROOT = Path(__file__).resolve().parents[2]
FIXTURE_REPO = ROOT / "workspace" / "fixtures" / "buggy-repo"


def _fixture_repo_available() -> bool:
    return (
        FIXTURE_REPO.exists()
        and (FIXTURE_REPO / "src" / "parser.py").exists()
        and (FIXTURE_REPO / ".git").exists()
    )


def _reset_fixture_repo() -> None:
    """Hard-reset the fixture repo to its initial committed state."""
    subprocess.run(
        ["git", "-C", str(FIXTURE_REPO), "checkout", "--", "."],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "-C", str(FIXTURE_REPO), "clean", "-fd"],
        check=True,
        capture_output=True,
    )


# ── Tests ─────────────────────────────────────────────────────────────────────


@requires_runtime
class TestRealBugFix:
    """End-to-end proof that the hardened worker can fix the bundled fixture bug."""

    def setup_method(self) -> None:
        if not _fixture_repo_available():
            pytest.skip(
                "Fixture repo not materialised — run scripts/materialize_repos.sh first"
            )
        _reset_fixture_repo()

    def test_worker_produces_patch_for_fixture_bug(self, tmp_path):
        """Worker must produce a non-empty diff for the known fixture bug."""
        from integration.shared_py.models import (
            Constraints,
            ProposeContext,
            ProposeRequest,
        )
        from integration.worker_hardened.bridge import run_hardened

        req = ProposeRequest(
            run_id="e2e-real-bug-fix",
            repo_name="buggy-repo",
            repo_path=str(FIXTURE_REPO),
            task=(
                "Fix first_token so that calling it with an empty token list "
                "returns None instead of raising IndexError."
            ),
            mode="autonomous",
            context=ProposeContext(),
            constraints=Constraints(
                allowed_paths=["src/parser.py"],
                max_files=2,
                max_changed_lines=50,
            ),
        )

        result = run_hardened(req)

        assert result["diff"], (
            "Worker should produce a non-empty diff. "
            "If this fails, check that the heuristic fallback is working in bridge.py. "
            f"Worker warnings: {result.get('warnings', [])}"
        )

    def test_patch_touches_parser_file(self, tmp_path):
        """The produced diff must include src/parser.py."""
        from integration.shared_py.models import Constraints, ProposeContext, ProposeRequest
        from integration.worker_hardened.bridge import run_hardened

        req = ProposeRequest(
            run_id="e2e-parser-touch",
            repo_name="buggy-repo",
            repo_path=str(FIXTURE_REPO),
            task=(
                "Fix first_token so that calling it with an empty token list "
                "returns None instead of raising IndexError."
            ),
            mode="autonomous",
            context=ProposeContext(),
            constraints=Constraints(
                allowed_paths=["src/parser.py"],
                max_files=2,
                max_changed_lines=50,
            ),
        )

        result = run_hardened(req)

        touched = result.get("touched_files", [])
        assert any("parser" in f for f in touched), (
            f"src/parser.py should be in touched_files, got: {touched}"
        )

    def test_fix_makes_test_suite_pass(self):
        """After running the worker, pytest tests/test_parser.py must pass."""
        from integration.shared_py.models import Constraints, ProposeContext, ProposeRequest
        from integration.worker_hardened.bridge import run_hardened

        req = ProposeRequest(
            run_id="e2e-test-pass",
            repo_name="buggy-repo",
            repo_path=str(FIXTURE_REPO),
            task=(
                "Fix first_token so that calling it with an empty token list "
                "returns None instead of raising IndexError."
            ),
            mode="autonomous",
            context=ProposeContext(),
            constraints=Constraints(
                allowed_paths=["src/parser.py"],
                max_files=2,
                max_changed_lines=50,
            ),
        )

        result = run_hardened(req)

        if not result["diff"]:
            pytest.skip("Worker produced no diff; skipping test-pass assertion")

        # Run the bundled test suite against the (now patched) fixture
        proc = subprocess.run(
            [sys.executable, "-m", "pytest", "tests/", "-q", "--tb=short"],
            cwd=str(FIXTURE_REPO),
            capture_output=True,
            text=True,
        )

        assert proc.returncode == 0, (
            "test_parser.py should pass after applying the worker patch.\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )

    def test_fix_returns_none_for_empty_list(self):
        """The patched parser must return None for an empty token list (semantic check)."""
        import importlib
        import importlib.util

        from integration.shared_py.models import Constraints, ProposeContext, ProposeRequest
        from integration.worker_hardened.bridge import run_hardened

        req = ProposeRequest(
            run_id="e2e-semantic",
            repo_name="buggy-repo",
            repo_path=str(FIXTURE_REPO),
            task=(
                "Fix first_token so that calling it with an empty token list "
                "returns None instead of raising IndexError."
            ),
            mode="autonomous",
            context=ProposeContext(),
            constraints=Constraints(
                allowed_paths=["src/parser.py"],
                max_files=2,
                max_changed_lines=50,
            ),
        )

        result = run_hardened(req)

        if not result["diff"]:
            pytest.skip("Worker produced no diff; skipping semantic check")

        # Dynamically load the patched module
        parser_path = FIXTURE_REPO / "src" / "parser.py"
        spec = importlib.util.spec_from_file_location("_patched_parser", parser_path)
        assert spec and spec.loader
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)  # type: ignore[union-attr]

        assert module.first_token([]) is None, (
            "first_token([]) should return None after the fix"
        )
        assert module.first_token(["a", "b"]) == "a", (
            "first_token(['a', 'b']) should still return 'a'"
        )
