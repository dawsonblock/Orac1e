"""Comprehensive e2e tests for promotion flow.

This module provides dedicated tests for the coding run promotion flow:
1. Happy path promotion
2. Validation failure rollback
3. Patch application and commit
4. Status transitions
5. Receipt persistence
6. Edge cases and error handling
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from scripts import coding_run_promotion as crp


class TestPromotionFlowHappyPath:
    """Tests for the happy path promotion flow."""

    def test_promotion_flow_basic(self, promotion_env):
        """Test basic promotion flow from awaiting_approval to applied."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('promoted')\n", encoding="utf-8")

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="basic promotion"
        )

        # Verify promotion result
        assert result.status == "applied", \
            "Promotion should result in 'applied' status"
        assert result.validation_ok is True, \
            "Validation should succeed"

    def test_promotion_updates_canonical(self, promotion_env):
        """Test that promotion updates canonical repository."""
        worktree = promotion_env["worktree"]
        new_content = "print('canonical update')\n"
        (worktree / "app.py").write_text(new_content, encoding="utf-8")

        crp.promote_run(promotion_env["run_id"], actor="tester", note="update canonical")

        # Verify canonical was updated
        canonical_content = (promotion_env["canonical"] / "app.py").read_text(encoding="utf-8")
        assert "canonical update" in canonical_content, \
            "Canonical should contain promoted changes"

    def test_promotion_creates_git_commit(self, promotion_env):
        """Test that promotion creates a git commit."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('committed')\n", encoding="utf-8")

        crp.promote_run(promotion_env["run_id"], actor="tester", note="create commit")

        # Check commit was created
        commits = subprocess.run(
            ["git", "-C", str(promotion_env["canonical"]), "log", "--oneline"],
            capture_output=True,
            text=True,
        ).stdout.strip()

        assert len(commits.split("\n")) >= 2, \
            "Should have at least 2 commits (initial + promotion)"

    def test_promotion_records_commit_message(self, promotion_env):
        """Test that promotion commit has correct message."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('message test')\n", encoding="utf-8")

        crp.promote_run(promotion_env["run_id"], actor="tester", note="test message")

        commit_message = subprocess.run(
            ["git", "-C", str(promotion_env["canonical"]), "log", "-1", "--pretty=%s"],
            capture_output=True,
            text=True,
        ).stdout.strip()

        expected = f"Promote approved coding run {promotion_env['run_id']}"
        assert commit_message == expected, \
            f"Commit message should be '{expected}'"


class TestPromotionValidation:
    """Tests for promotion validation flow."""

    def test_promotion_with_syntax_validation(self, promotion_env):
        """Test promotion with Python syntax validation."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('valid')\n", encoding="utf-8")

        # Update metadata with validation
        metadata = json.loads(
            (promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json").read_text()
        )
        metadata["validationCommands"] = ["python3 -m py_compile app.py"]
        (promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json").write_text(
            json.dumps(metadata, indent=2)
        )

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="syntax ok"
        )

        assert result.status == "applied", \
            "Valid syntax should pass validation"

    def test_promotion_validation_failure_rollback(self, promotion_env):
        """Test that validation failure rolls back changes."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('broken'\n", encoding="utf-8")

        # Update metadata with validation
        metadata = json.loads(
            (promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json").read_text()
        )
        metadata["validationCommands"] = ["python3 -m py_compile app.py"]
        (promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json").write_text(
            json.dumps(metadata, indent=2)
        )

        with pytest.raises(crp.PromotionError):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="should fail")

        # Verify canonical was rolled back
        canonical_content = (promotion_env["canonical"] / "app.py").read_text(encoding="utf-8")
        assert "hello" in canonical_content, \
            "Canonical should be rolled back to original content"

    def test_promotion_validation_failure_canonical_clean(self, promotion_env):
        """Test that failed promotion leaves canonical repo clean."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('broken'\n", encoding="utf-8")

        # Update metadata with validation
        metadata = json.loads(
            (promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json").read_text()
        )
        metadata["validationCommands"] = ["python3 -m py_compile app.py"]
        (promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json").write_text(
            json.dumps(metadata, indent=2)
        )

        try:
            crp.promote_run(promotion_env["run_id"], actor="tester", note="should fail")
        except crp.PromotionError:
            pass

        # Verify canonical repo is clean (no uncommitted changes)
        git_status = subprocess.run(
            ["git", "-C", str(promotion_env["canonical"]), "status", "--porcelain"],
            capture_output=True,
            text=True,
        ).stdout.strip()

        assert git_status == "", \
            "Canonical should be clean after rollback"


class TestPromotionStatusTransitions:
    """Tests for promotion status transitions."""

    def test_status_awaiting_approval_to_applied(self, promotion_env):
        """Test transition from awaiting_approval to applied."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        runs = json.loads(
            (promotion_env["runs_root"] / "runs.json").read_text(encoding="utf-8")
        )
        assert runs[0]["status"] == "applied", \
            "Status should transition to 'applied'"

    def test_status_awaiting_approval_to_rejected(self, promotion_env):
        """Test transition from awaiting_approval to rejected."""
        crp.reject_run(promotion_env["run_id"], actor="tester", note="reject")

        runs = json.loads(
            (promotion_env["runs_root"] / "runs.json").read_text(encoding="utf-8")
        )
        assert runs[0]["status"] == "rejected", \
            "Status should transition to 'rejected'"

    def test_status_running_to_applied_is_rejected(self, promotion_env):
        """Test that promotion from running status is rejected (requires awaiting_approval)."""
        # Update status to running
        runs = json.loads(
            (promotion_env["runs_root"] / "runs.json").read_text(encoding="utf-8")
        )
        runs[0]["status"] = "running"
        (promotion_env["runs_root"] / "runs.json").write_text(
            json.dumps(runs, indent=2), encoding="utf-8"
        )

        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        with pytest.raises(crp.PromotionError, match="not awaiting approval"):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="should fail")

    def test_status_running_to_rejected_is_rejected(self, promotion_env):
        """Test that rejection from running status is rejected (requires awaiting_approval)."""
        # Update status to running
        runs = json.loads(
            (promotion_env["runs_root"] / "runs.json").read_text(encoding="utf-8")
        )
        runs[0]["status"] = "running"
        (promotion_env["runs_root"] / "runs.json").write_text(
            json.dumps(runs, indent=2), encoding="utf-8"
        )

        with pytest.raises(crp.PromotionError, match="not awaiting approval"):
            crp.reject_run(promotion_env["run_id"], actor="tester", note="should fail")


class TestPromotionReceipts:
    """Tests for promotion receipt handling."""

    def test_approval_receipt_fields(self, promotion_env):
        """Test that approval receipt contains all required fields."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        crp.promote_run(
            promotion_env["run_id"], actor="tester", note="receipt test"
        )

        receipt_path = (
            promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
        )
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))

        required_fields = ["run_id", "decision", "actor", "note", "at"]
        for field in required_fields:
            assert field in receipt, f"Receipt should have '{field}' field"

    def test_promotion_receipt_fields(self, promotion_env):
        """Test that promotion receipt contains all required fields."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="promotion receipt"
        )

        receipt = json.loads(open(result.receipt_path).read())

        required_fields = [
            "run_id", "actor", "note", "at", "canonical_repo",
            "worktree_repo", "status", "validation_ok"
        ]
        for field in required_fields:
            assert field in receipt, f"Receipt should have '{field}' field"

    def test_rejection_receipt_fields(self, promotion_env):
        """Test that rejection receipt contains all required fields."""
        crp.reject_run(promotion_env["run_id"], actor="tester", note="rejection test")

        receipt_path = (
            promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
        )
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))

        assert receipt["decision"] == "rejected"
        assert receipt["run_id"] == promotion_env["run_id"]


class TestPromotionArtifacts:
    """Tests for promotion artifact creation."""

    def test_patch_artifact_contains_changes(self, promotion_env):
        """Test that patch artifact contains the changes."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('patched')\n", encoding="utf-8")

        crp.promote_run(promotion_env["run_id"], actor="tester", note="create patch")

        patch_path = (
            promotion_env["runs_root"] / "artifacts" / f"{promotion_env['run_id']}.patch"
        )

        assert patch_path.exists(), "Patch artifact should exist"

        patch_content = patch_path.read_text(encoding="utf-8")
        assert len(patch_content) > 0, "Patch should not be empty"

    def test_validation_artifacts_created(self, promotion_env):
        """Test that validation artifacts are created for both worktree and canonical."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('validated')\n", encoding="utf-8")

        crp.promote_run(promotion_env["run_id"], actor="tester", note="validation test")

        validation_dir = promotion_env["runs_root"] / "validation"

        worktree_artifact = validation_dir / f"{promotion_env['run_id']}.worktree.json"
        canonical_artifact = validation_dir / f"{promotion_env['run_id']}.canonical.json"

        assert worktree_artifact.exists(), "Worktree validation artifact should exist"
        assert canonical_artifact.exists(), "Canonical validation artifact should exist"


class TestPromotionEdgeCases:
    """Tests for promotion edge cases."""

    def test_promotion_with_multiple_files(self, promotion_env):
        """Test promotion with multiple file changes."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('file1')\n", encoding="utf-8")
        (worktree / "new_file.py").write_text("print('file2')\n", encoding="utf-8")

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="multi-file"
        )

        assert result.status == "applied", \
            "Multi-file promotion should succeed"

    def test_promotion_with_binary_file(self, promotion_env):
        """Test promotion with binary file changes."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('binary test')\n", encoding="utf-8")
        (worktree / "data.bin").write_bytes(b"\x00\x01\x02\x03")

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="with binary"
        )

        assert result.status == "applied", \
            "Promotion with binary should succeed"

    def test_promotion_idempotent_on_applied(self, promotion_env):
        """Test that promoting an already applied run is idempotent."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('first')\n", encoding="utf-8")

        # First promotion
        result1 = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="first"
        )
        assert result1.status == "applied"

        # Second promotion should also succeed
        result2 = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="second"
        )
        assert result2.status == "applied", \
            "Second promotion should succeed (idempotent)"


class TestPromotionErrorHandling:
    """Tests for promotion error handling."""

    def test_promotion_with_invalid_run_id(self, promotion_env):
        """Test promotion with invalid run ID raises error."""
        with pytest.raises(crp.PromotionError, match="run not found"):
            crp.promote_run("invalid-run-id", actor="tester", note="test")

    def test_promotion_with_dirty_canonical(self, promotion_env):
        """Test promotion refuses dirty canonical repo."""
        (promotion_env["canonical"] / "dirty.txt").write_text("dirty\n", encoding="utf-8")
        (promotion_env["worktree"] / "app.py").write_text("print('update')\n", encoding="utf-8")

        with pytest.raises(crp.PromotionError, match="canonical repo is dirty"):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="dirty canonical")

    def test_promotion_with_empty_diff(self, promotion_env):
        """Test promotion refuses empty diff."""
        # Don't modify worktree at all

        with pytest.raises(crp.PromotionError, match="no diff found"):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="empty diff")

    def test_promotion_with_worktree_lineage_mismatch(self, promotion_env):
        """Test promotion refuses worktree with mismatched lineage."""
        # Reset canonical to create lineage mismatch
        subprocess.run(
            ["git", "-C", str(promotion_env["canonical"]), "reset", "--hard", "HEAD~1"],
            check=True,
        )

        (promotion_env["worktree"] / "app.py").write_text("print('update')\n", encoding="utf-8")

        with pytest.raises(crp.PromotionError, match="lineage"):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="lineage mismatch")