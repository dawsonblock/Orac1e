"""E2E tests for parallel orchestrator.

This module tests the ParallelOrchestrator class for batch execution
of multiple coding tasks.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

from integration.orchestrator import ParallelOrchestrator, run_parallel_session


@pytest.fixture
def multi_file_repo(tmp_path):
    """Create a repository with multiple files to modify."""
    repo = tmp_path / "multi_repo"
    repo.mkdir()

    # Initialize git repo
    subprocess.run(["git", "init", str(repo)], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@test.com"], check=True)

    # Create multiple buggy files
    files = {
        "parser.py": '''def first_token(tokens):
    return tokens[0]

def last_token(tokens):
    return tokens[-1]
''',
        "validator.py": '''def validate_input(data):
    if data is None:
        return False
    return True
''',
        "utils.py": '''def safe_get(lst, index):
    return lst[index]

def safe_divide(a, b):
    return a / b
''',
    }

    for filename, content in files.items():
        (repo / filename).write_text(content, encoding="utf-8")

    # Commit all files
    subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-m", "initial commit"], check=True, capture_output=True)

    return repo


@pytest.mark.skipif(
    not os.environ.get("DEEPSEEK_API_KEY"),
    reason="DEEPSEEK_API_KEY not set"
)
class TestParallelOrchestrator:
    """Test parallel orchestrator functionality."""

    def test_orchestrator_initialization(self):
        """Test that orchestrator initializes correctly."""
        orchestrator = ParallelOrchestrator(max_workers=2, per_worker_semaphore=1)

        assert orchestrator.max_workers == 2
        assert orchestrator.executor is not None

    def test_orchestrator_executes_single_task(self, multi_file_repo):
        """Test that orchestrator can execute a single task."""
        orchestrator = ParallelOrchestrator(max_workers=1, per_worker_semaphore=1)

        tasks = [
            {"task": "Fix first_token to handle empty list", "repo_path": str(multi_file_repo)}
        ]

        results = orchestrator.execute_batch(tasks)

        assert len(results) == 1
        assert "success" in results[0]

    def test_orchestrator_executes_multiple_tasks(self, multi_file_repo):
        """Test that orchestrator can execute multiple tasks in parallel."""
        orchestrator = ParallelOrchestrator(max_workers=2, per_worker_semaphore=1)

        tasks = [
            {"task": "Fix first_token to handle empty list", "repo_path": str(multi_file_repo)},
            {"task": "Add error handling to safe_get", "repo_path": str(multi_file_repo)},
        ]

        results = orchestrator.execute_batch(tasks)

        assert len(results) == 2
        for result in results:
            assert "success" in result

    def test_orchestrator_handles_task_failure(self, multi_file_repo):
        """Test that orchestrator handles individual task failures gracefully."""
        orchestrator = ParallelOrchestrator(max_workers=2, per_worker_semaphore=1)

        tasks = [
            {"task": "Fix first_token to handle empty list", "repo_path": str(multi_file_repo)},
            {"task": "Impossible task that cannot be done", "repo_path": str(multi_file_repo)},
        ]

        results = orchestrator.execute_batch(tasks)

        assert len(results) == 2
        # At least one should have succeeded or both failed gracefully
        for result in results:
            assert isinstance(result, dict)

    def test_orchestrator_respects_semaphore(self, multi_file_repo):
        """Test that orchestrator respects semaphore limits."""
        orchestrator = ParallelOrchestrator(max_workers=4, per_worker_semaphore=1)

        tasks = [
            {"task": f"Task {i}", "repo_path": str(multi_file_repo)}
            for i in range(4)
        ]

        results = orchestrator.execute_batch(tasks)

        assert len(results) == 4


@pytest.mark.skipif(
    not os.environ.get("DEEPSEEK_API_KEY"),
    reason="DEEPSEEK_API_KEY not set"
)
class TestRunParallelSession:
    """Test the run_parallel_session convenience function."""

    def test_run_parallel_session_returns_results(self, multi_file_repo):
        """Test that run_parallel_session returns results."""
        tasks = [
            {"task": "Fix first_token to handle empty list", "repo_path": str(multi_file_repo)},
        ]

        results = run_parallel_session(tasks)

        assert len(results) == 1
        assert "success" in results[0]

    def test_run_parallel_session_prints_output(self, multi_file_repo, capsys):
        """Test that run_parallel_session prints status output."""
        tasks = [
            {"task": "Fix first_token to handle empty list", "repo_path": str(multi_file_repo)},
        ]

        run_parallel_session(tasks)

        captured = capsys.readouterr()
        assert "Task 1:" in captured.out


class TestParallelOrchestratorEdgeCases:
    """Test edge cases for parallel orchestrator."""

    def test_orchestrator_with_empty_task_list(self):
        """Test that orchestrator handles empty task list."""
        orchestrator = ParallelOrchestrator(max_workers=2, per_worker_semaphore=1)

        results = orchestrator.execute_batch([])

        assert results == []

    def test_orchestrator_with_invalid_repo_path(self):
        """Test that orchestrator handles invalid repo paths gracefully."""
        orchestrator = ParallelOrchestrator(max_workers=1, per_worker_semaphore=1)

        tasks = [
            {"task": "Fix bug", "repo_path": "/nonexistent/path"}
        ]

        results = orchestrator.execute_batch(tasks)

        assert len(results) == 1
        # Should fail gracefully
        assert isinstance(results[0], dict)
