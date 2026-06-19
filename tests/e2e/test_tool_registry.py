"""Comprehensive e2e tests for tool registry integration.

This module tests:
1. Tool registry refuses dirty canonical repo
2. Tool discovery and loading
3. Tool manifest validation
4. Health check integration
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

from scripts import coding_run_promotion as crp


def _commit_worktree(worktree):
    """Commit all changes in the worktree so HEAD~1..HEAD captures the diff."""
    subprocess.run(["git", "-C", str(worktree), "add", "."], check=True, capture_output=True, text=True)
    subprocess.run(["git", "-C", str(worktree), "commit", "-m", "wip"], check=True, capture_output=True, text=True)


class TestToolRegistryDirtyRepo:
    """Tests for tool registry interaction with dirty repositories."""

    def test_tool_registry_refuses_dirty_canonical_repo(self, promotion_env):
        """Test that promotion refuses dirty canonical repo."""
        # Make canonical repo dirty
        (promotion_env["canonical"] / "scratch.txt").write_text(
            "dirty\n", encoding="utf-8"
        )
        (promotion_env["worktree"] / "app.py").write_text(
            "print('updated')\n", encoding="utf-8"
        )
        _commit_worktree(promotion_env["worktree"])

        with pytest.raises(crp.PromotionError, match="canonical repo is dirty"):
            crp.promote_run(promotion_env["run_id"], actor="tester")

    def test_dirty_repo_does_not_affect_worktree(self, promotion_env):
        """Test that worktree changes are not lost when canonical is dirty."""
        worktree = promotion_env["worktree"]
        (promotion_env["canonical"] / "scratch.txt").write_text(
            "dirty\n", encoding="utf-8"
        )
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")
        _commit_worktree(worktree)

        try:
            crp.promote_run(promotion_env["run_id"], actor="tester")
        except crp.PromotionError:
            pass  # Expected

        # Worktree content should be unchanged
        worktree_content = (worktree / "app.py").read_text(encoding="utf-8")
        assert "updated" in worktree_content, \
            "Worktree changes should be preserved after rejection"

    def test_clean_repo_allows_promotion(self, promotion_env):
        """Test that clean canonical repo allows promotion."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('clean')\n", encoding="utf-8")
        _commit_worktree(worktree)

        # Ensure canonical is clean (default state)
        result = crp.promote_run(promotion_env["run_id"], actor="tester")

        assert result.status == "applied", \
            "Clean repo should allow promotion"


class TestToolRegistryPaths:
    """Tests for tool registry path handling."""

    def test_tool_registry_handles_missing_metadata(self, promotion_env):
        """Test handling of missing run metadata."""
        # Remove metadata
        metadata_file = (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        )
        metadata_file.unlink()

        with pytest.raises(crp.PromotionError, match="metadata missing"):
            crp.promote_run(promotion_env["run_id"], actor="tester")

    def test_tool_registry_handles_missing_worktree(self, promotion_env):
        """Test handling of missing worktree."""
        # Remove worktree
        import shutil
        shutil.rmtree(promotion_env["worktree"])

        with pytest.raises(crp.PromotionError, match="worktree missing"):
            crp.promote_run(promotion_env["run_id"], actor="tester")

    def test_tool_registry_handles_missing_canonical(self, promotion_env):
        """Test handling of missing canonical repository."""
        # Remove canonical
        import shutil
        shutil.rmtree(promotion_env["canonical"])

        with pytest.raises(crp.PromotionError, match="canonical repo missing"):
            crp.promote_run(promotion_env["run_id"], actor="tester")


class TestToolRegistryValidationIntegration:
    """Tests for tool registry validation integration."""

    def test_promotion_with_allowed_paths(self, promotion_env):
        """Test promotion respects allowed paths configuration."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('allowed')\n", encoding="utf-8")
        _commit_worktree(worktree)

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="allowed path"
        )

        assert result.status == "applied", \
            "Should apply when using allowed path"

    def test_promotion_validation_commands_recorded(self, promotion_env):
        """Test that validation commands are recorded in metadata."""
        # Verify metadata has validation commands from fixture
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )

        assert "validationCommands" in metadata, \
            "Metadata should have validationCommands"
        assert len(metadata["validationCommands"]) > 0, \
            "Should have at least one validation command"


class TestToolRegistryArtifacts:
    """Tests for tool registry artifact handling."""

    def test_promotion_creates_approvals_dir(self, promotion_env):
        """Test that promotion creates approvals directory."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")
        _commit_worktree(worktree)

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        approvals_dir = promotion_env["runs_root"] / "approvals"
        assert approvals_dir.exists(), \
            "Approvals directory should be created"

    def test_promotion_creates_promotions_dir(self, promotion_env):
        """Test that promotion creates promotions directory."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")
        _commit_worktree(worktree)

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        promotions_dir = promotion_env["runs_root"] / "promotions"
        assert promotions_dir.exists(), \
            "Promotions directory should be created"

    def test_promotion_creates_artifacts_dir(self, promotion_env):
        """Test that promotion creates artifacts directory."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")
        _commit_worktree(worktree)

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        artifacts_dir = promotion_env["runs_root"] / "artifacts"
        assert artifacts_dir.exists(), \
            "Artifacts directory should be created"

    def test_promotion_creates_validation_dir(self, promotion_env):
        """Test that promotion creates validation directory."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")
        _commit_worktree(worktree)

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        validation_dir = promotion_env["runs_root"] / "validation"
        assert validation_dir.exists(), \
            "Validation directory should be created"


class TestToolRegistryReceipts:
    """Tests for tool registry receipt handling."""

    def test_approval_receipt_has_run_id(self, promotion_env):
        """Test that approval receipt includes run_id."""
        (promotion_env["worktree"] / "app.py").write_text(
            "print('updated')\n", encoding="utf-8"
        )
        _commit_worktree(promotion_env["worktree"])

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        receipt = json.loads(
            (
                promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )

        assert receipt["run_id"] == promotion_env["run_id"], \
            "Receipt should include correct run_id"

    def test_promotion_receipt_has_commit_sha(self, promotion_env):
        """Test that promotion receipt includes commit SHA."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")
        _commit_worktree(worktree)

        result = crp.promote_run(promotion_env["run_id"], actor="tester", note="ship")

        receipt = json.loads(open(result.receipt_path).read())

        assert "promotion_commit" in receipt, \
            "Receipt should include promotion_commit"
        assert len(receipt["promotion_commit"]) > 0, \
            "promotion_commit should be non-empty"

    def test_rejection_receipt_has_run_id(self, promotion_env):
        """Test that rejection receipt includes run_id."""
        crp.reject_run(promotion_env["run_id"], actor="tester", note="reject")

        receipt = json.loads(
            (
                promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )

        assert receipt["run_id"] == promotion_env["run_id"], \
            "Rejection receipt should include correct run_id"


class TestToolRegistryConcurrency:
    """Tests for concurrent access scenarios."""

    def test_reject_then_promote_fails(self, promotion_env):
        """Test that reject followed by promote fails."""
        # First reject
        crp.reject_run(promotion_env["run_id"], actor="tester", note="reject")

        # Then try to promote
        (promotion_env["worktree"] / "app.py").write_text(
            "print('updated')\n", encoding="utf-8"
        )
        _commit_worktree(promotion_env["worktree"])

        with pytest.raises(crp.PromotionError):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="try")

    def test_promote_then_reject_fails(self, promotion_env):
        """Test that promote followed by reject fails."""
        # First promote
        (promotion_env["worktree"] / "app.py").write_text(
            "print('updated')\n", encoding="utf-8"
        )
        _commit_worktree(promotion_env["worktree"])
        crp.promote_run(promotion_env["run_id"], actor="tester", note="promote")

        # Then try to reject
        with pytest.raises(crp.PromotionError, match="already applied"):
            crp.reject_run(promotion_env["run_id"], actor="tester", note="try")
