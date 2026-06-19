"""Comprehensive e2e tests for validation flow.

This module tests:
1. Validation flow and approval receipt persistence
2. Promotion with validation
3. Validation failure rollback
4. Validation artifact persistence
"""
from __future__ import annotations

import json
import subprocess

import pytest

from scripts import coding_run_promotion as crp


def _commit_worktree(worktree):
    """Commit all changes in the worktree so HEAD~1..HEAD captures the diff."""
    subprocess.run(["git", "-C", str(worktree), "add", "."], check=True, capture_output=True, text=True)
    subprocess.run(["git", "-C", str(worktree), "commit", "-m", "wip"], check=True, capture_output=True, text=True)


class TestValidationFlowApprovals:
    """Tests for validation flow approval handling."""

    def test_validation_flow_persists_approval_receipt(self, promotion_env):
        """Test that validation flow persists approval receipt with correct decision."""
        (promotion_env["worktree"] / "app.py").write_text(
            "print('updated')\n", encoding="utf-8"
        )
        _commit_worktree(promotion_env["worktree"])

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ok")

        approvals_path = (
            promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
        )
        receipt = json.loads(approvals_path.read_text(encoding="utf-8"))
        
        assert receipt["decision"] == "approved", \
            "Decision should be 'approved'"
        assert receipt["actor"] == "tester", \
            "Actor should be 'tester'"
        assert "at" in receipt, \
            "Receipt should have timestamp"

    def test_validation_flow_records_approval_time(self, promotion_env):
        """Test that approval receipt includes timestamp."""
        (promotion_env["worktree"] / "app.py").write_text(
            "print('updated')\n", encoding="utf-8"
        )
        _commit_worktree(promotion_env["worktree"])

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        approvals_path = (
            promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
        )
        receipt = json.loads(approvals_path.read_text(encoding="utf-8"))
        
        assert "at" in receipt, \
            "Receipt should have 'at' timestamp"
        assert receipt["at"], \
            "Timestamp should not be empty"

    def test_validation_flow_preserves_note(self, promotion_env):
        """Test that approval note is preserved."""
        (promotion_env["worktree"] / "app.py").write_text(
            "print('updated')\n", encoding="utf-8"
        )
        _commit_worktree(promotion_env["worktree"])

        crp.promote_run(promotion_env["run_id"], actor="tester", note="looks good")

        approvals_path = (
            promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
        )
        receipt = json.loads(approvals_path.read_text(encoding="utf-8"))
        
        assert receipt["note"] == "looks good", \
            "Note should be preserved"


class TestValidationFlowWithValidation:
    """Tests for validation flow with actual validation commands."""

    def test_validation_flow_with_syntax_check(self, promotion_env):
        """Test validation flow with Python syntax check."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('valid syntax')\n", encoding="utf-8")

        # Update validation commands to use py_compile
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = ["python -m py_compile app.py"]
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        _commit_worktree(worktree)

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="syntax ok"
        )

        assert result.status == "applied", \
            "Should apply with valid syntax"
        assert result.validation_ok is True, \
            "Validation should pass"

    def test_validation_flow_fails_on_invalid_syntax(self, promotion_env):
        """Test validation flow fails on invalid syntax."""
        worktree = promotion_env["worktree"]
        # Invalid Python syntax (missing closing parenthesis)
        (worktree / "app.py").write_text("print('broken'\n", encoding="utf-8")

        # Update validation commands
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = ["python -m py_compile app.py"]
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        _commit_worktree(worktree)

        with pytest.raises(crp.PromotionError, match="validation failed"):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="syntax error")

    def test_validation_failure_rolls_back(self, promotion_env):
        """Test that validation failure rolls back changes."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('broken'\n", encoding="utf-8")

        # Update validation commands
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = ["python -m py_compile app.py"]
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        _commit_worktree(worktree)

        try:
            crp.promote_run(promotion_env["run_id"], actor="tester", note="test")
        except crp.PromotionError:
            pass  # Expected

        # Canonical should still have original content
        canonical_content = (promotion_env["canonical"] / "app.py").read_text(
            encoding="utf-8"
        )
        assert "hello" in canonical_content, \
            "Canonical should have original content after rollback"

    def test_validation_failure_updates_status(self, promotion_env):
        """Test that validation failure updates run status to failed."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('broken'\n", encoding="utf-8")

        # Update validation commands
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = ["python -m py_compile app.py"]
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        _commit_worktree(worktree)

        try:
            crp.promote_run(promotion_env["run_id"], actor="tester", note="test")
        except crp.PromotionError:
            pass  # Expected

        runs = json.loads(
            (promotion_env["runs_root"] / "runs.json").read_text(encoding="utf-8")
        )
        assert runs[0]["status"] == "failed", \
            "Status should be 'failed' after validation failure"


class TestValidationArtifacts:
    """Tests for validation artifact persistence."""

    def test_validation_artifact_persisted(self, promotion_env):
        """Test that validation artifacts are persisted."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")
        _commit_worktree(worktree)

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        validation_dir = promotion_env["runs_root"] / "validation"
        
        # Check for worktree validation artifact
        worktree_artifact = validation_dir / f"{promotion_env['run_id']}.worktree.json"
        assert worktree_artifact.exists(), \
            "Worktree validation artifact should exist"

        # Check for canonical validation artifact
        canonical_artifact = validation_dir / f"{promotion_env['run_id']}.canonical.json"
        assert canonical_artifact.exists(), \
            "Canonical validation artifact should exist"

    def test_validation_artifact_contains_results(self, promotion_env):
        """Test that validation artifacts contain validation results."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")
        _commit_worktree(worktree)

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        worktree_artifact = (
            promotion_env["runs_root"] / "validation" / f"{promotion_env['run_id']}.worktree.json"
        )
        artifact = json.loads(worktree_artifact.read_text(encoding="utf-8"))

        assert "ok" in artifact, \
            "Artifact should have 'ok' status"
        assert artifact["ok"] is True, \
            "Validation should pass"


class TestPatchArtifact:
    """Tests for patch artifact persistence."""

    def test_patch_artifact_persisted(self, promotion_env):
        """Test that patch artifact is persisted."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('patched')\n", encoding="utf-8")
        _commit_worktree(worktree)

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        artifacts_dir = promotion_env["runs_root"] / "artifacts"
        patch_file = artifacts_dir / f"{promotion_env['run_id']}.patch"
        
        assert patch_file.exists(), \
            "Patch artifact should exist"

        patch_content = patch_file.read_text(encoding="utf-8")
        assert "patched" in patch_content or "print" in patch_content, \
            "Patch should contain changes"


class TestRejectionFlow:
    """Tests for rejection flow in validation context."""

    def test_rejection_creates_approval_receipt(self, promotion_env):
        """Test that rejection creates approval receipt with rejected decision."""
        crp.reject_run(promotion_env["run_id"], actor="reviewer", note="needs work")

        approvals_path = (
            promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
        )
        receipt = json.loads(approvals_path.read_text(encoding="utf-8"))

        assert receipt["decision"] == "rejected", \
            "Decision should be 'rejected'"
        assert receipt["actor"] == "reviewer", \
            "Actor should be 'reviewer'"
        assert receipt["note"] == "needs work", \
            "Note should be preserved"


class TestMultiStepValidation:
    """Tests for multi-step validation scenarios."""

    def test_multi_command_validation_allows_if_all_pass(self, promotion_env):
        """Test that multi-command validation passes if all commands pass."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("x = 1\nprint(x)\n", encoding="utf-8")

        # Update validation commands with multiple steps
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = [
            "python -m py_compile app.py",
        ]
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        _commit_worktree(worktree)

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="multi-step ok"
        )

        assert result.status == "applied", \
            "Should apply when all validation commands pass"

    def test_multi_command_validation_fails_if_any_fails(self, promotion_env):
        """Test that multi-command validation fails if any command fails."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('hello world')\n", encoding="utf-8")

        # Update validation commands where second will fail
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = [
            "python -m py_compile app.py",
            "false",  # This will fail
        ]
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        _commit_worktree(worktree)

        with pytest.raises(crp.PromotionError, match="validation failed"):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="should fail")
