"""Comprehensive e2e tests for interactive run handling.

This module tests:
1. Interactive run promotion and commit
2. Approval receipt persistence
3. Run status transitions
4. Idempotent promotion handling
"""
from __future__ import annotations

import json
import subprocess

import pytest

from scripts import coding_run_promotion as crp


class TestInteractiveRunPromotion:
    """Tests for interactive run promotion functionality."""

    def test_interactive_run_promotes_and_commits(self, promotion_env):
        """Test that interactive run promotion commits changes to canonical repo."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="ship it"
        )

        assert result.status == "applied", \
            "Promotion should succeed with status 'applied'"

        # Verify commit was made
        head_message = subprocess.run(
            ["git", "-C", str(promotion_env["canonical"]), "log", "-1", "--pretty=%s"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        
        assert head_message == f"Promote approved coding run {promotion_env['run_id']}", \
            "Commit message should match expected format"

    def test_promotion_updates_canonical_content(self, promotion_env):
        """Test that promotion updates the canonical repository content."""
        worktree = promotion_env["worktree"]
        updated_content = "print('interactive update')\n"
        (worktree / "app.py").write_text(updated_content, encoding="utf-8")

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship it")

        canonical_content = (promotion_env["canonical"] / "app.py").read_text(
            encoding="utf-8"
        )
        
        assert "updated" in canonical_content, \
            "Canonical repo should contain the promoted content"

    def test_promotion_updates_runs_json_status(self, promotion_env):
        """Test that promotion updates the runs.json status."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship it")

        runs = json.loads(
            (promotion_env["runs_root"] / "runs.json").read_text(encoding="utf-8")
        )
        
        assert runs[0]["status"] == "applied", \
            "Run status should be updated to 'applied'"


class TestPromotionApprovalReceipt:
    """Tests for promotion approval receipt handling."""

    def test_validation_flow_persists_approval_receipt(self, promotion_env):
        """Test that validation flow persists approval receipt."""
        (promotion_env["worktree"] / "app.py").write_text(
            "print('updated')\n", encoding="utf-8"
        )

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ok")

        approvals_path = (
            promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
        )
        
        assert approvals_path.exists(), \
            "Approval receipt file should exist"
        
        receipt = json.loads(approvals_path.read_text(encoding="utf-8"))
        
        assert receipt["decision"] == "approved", \
            "Receipt should show 'approved' decision"
        assert receipt["actor"] == "tester", \
            "Receipt should record the actor"

    def test_rejection_persists_rejection_receipt(self, promotion_env):
        """Test that rejection persists rejection receipt."""
        crp.reject_run(promotion_env["run_id"], actor="tester", note="not ready")

        approvals_path = (
            promotion_env["runs_root"] / "approvals" / f"{promotion_env['run_id']}.json"
        )
        
        assert approvals_path.exists(), \
            "Rejection receipt file should exist"
        
        receipt = json.loads(approvals_path.read_text(encoding="utf-8"))
        
        assert receipt["decision"] == "rejected", \
            "Receipt should show 'rejected' decision"
        assert receipt["actor"] == "tester", \
            "Receipt should record the actor"


class TestInteractiveRunIdempotency:
    """Tests for idempotent promotion handling."""

    def test_promote_already_applied_run_is_idempotent(self, promotion_env):
        """Test that promoting an already applied run is idempotent."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        # First promotion
        result1 = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="first"
        )
        assert result1.status == "applied"

        # Second promotion should be idempotent
        result2 = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="second"
        )
        assert result2.status == "applied", \
            "Second promotion should succeed (idempotent)"

    def test_reject_already_rejected_run_is_idempotent(self, promotion_env):
        """Test that rejecting an already rejected run is idempotent."""
        # First rejection
        result1 = crp.reject_run(
            promotion_env["run_id"], actor="tester", note="first"
        )
        assert result1["decision"] == "rejected"

        # Second rejection should be idempotent
        result2 = crp.reject_run(
            promotion_env["run_id"], actor="tester", note="second"
        )
        assert result2["decision"] == "rejected", \
            "Second rejection should succeed (idempotent)"


class TestPromotionErrorScenarios:
    """Tests for error scenarios in promotion."""

    def test_promote_nonexistent_run_raises(self, promotion_env):
        """Test that promoting a nonexistent run raises error."""
        with pytest.raises(crp.PromotionError, match="run not found"):
            crp.promote_run("nonexistent-id", actor="tester", note="test")

    def test_promote_with_dirty_canonical_raises(self, promotion_env):
        """Test that promoting with dirty canonical repo raises error."""
        # Make canonical repo dirty
        (promotion_env["canonical"] / "scratch.txt").write_text(
            "dirty\n", encoding="utf-8"
        )
        
        # Make worktree changes
        (promotion_env["worktree"] / "app.py").write_text(
            "print('updated')\n", encoding="utf-8"
        )

        with pytest.raises(crp.PromotionError, match="canonical repo is dirty"):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="test")

    def test_promote_with_empty_diff_raises(self, promotion_env):
        """Test that promoting with empty diff raises error."""
        # Don't make any changes to worktree

        with pytest.raises(crp.PromotionError, match="no diff found"):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="test")

    def test_promote_invalid_status_raises(self, promotion_env):
        """Test that promoting with invalid status raises error."""
        # Update run status to rejected
        runs = json.loads(
            (promotion_env["runs_root"] / "runs.json").read_text(encoding="utf-8")
        )
        runs[0]["status"] = "rejected"
        (promotion_env["runs_root"] / "runs.json").write_text(
            json.dumps(runs, indent=2), encoding="utf-8"
        )

        with pytest.raises(crp.PromotionError, match="not awaiting approval"):
            crp.promote_run(promotion_env["run_id"], actor="tester", note="test")


class TestPromotionEvents:
    """Tests for promotion event recording."""

    def test_promotion_records_events(self, promotion_env):
        """Test that promotion records events."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        crp.promote_run(promotion_env["run_id"], actor="tester", note="ship it")

        events_path = promotion_env["runs_root"] / "events.jsonl"
        assert events_path.exists(), "Events file should exist"

        events_content = events_path.read_text(encoding="utf-8")
        events = [
            json.loads(line)
            for line in events_content.strip().split("\n")
            if line
        ]

        event_types = {e.get("type") for e in events}
        assert "approval.recorded" in event_types, \
            "Should have approval.recorded event"
        assert "promotion.completed" in event_types, \
            "Should have promotion.completed event"

    def test_rejection_records_events(self, promotion_env):
        """Test that rejection records events."""
        crp.reject_run(promotion_env["run_id"], actor="tester", note="reject")

        events_path = promotion_env["runs_root"] / "events.jsonl"
        events_content = events_path.read_text(encoding="utf-8")
        events = [
            json.loads(line)
            for line in events_content.strip().split("\n")
            if line
        ]

        event_types = {e.get("type") for e in events}
        assert "approval.rejected" in event_types, \
            "Should have approval.rejected event"


class TestPromotionMetadata:
    """Tests for promotion metadata handling."""

    def test_promotion_receipt_contains_required_fields(self, promotion_env):
        """Test that promotion receipt contains all required fields."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="ship it"
        )

        receipt_path = result.receipt_path
        receipt = json.loads(open(receipt_path).read())

        required_fields = [
            "run_id",
            "actor",
            "note",
            "at",
            "canonical_repo",
            "worktree_repo",
            "status",
            "validation_ok",
        ]
        
        for field in required_fields:
            assert field in receipt, \
                f"Receipt should contain '{field}' field"

    def test_promotion_commit_sha_recorded(self, promotion_env):
        """Test that promotion records the commit SHA."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="ship it"
        )

        receipt = json.loads(open(result.receipt_path).read())
        
        assert "promotion_commit" in receipt, \
            "Receipt should contain promotion_commit"
        assert receipt["promotion_commit"], \
            "promotion_commit should not be empty"
