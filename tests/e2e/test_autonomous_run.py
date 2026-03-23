"""Comprehensive e2e tests for autonomous run handling.

This module tests:
1. Autonomous run rejection path
2. Run status transitions
3. Idempotent rejection handling
4. Error scenarios for autonomous runs
"""
from __future__ import annotations

import json
import subprocess

import pytest

from scripts import coding_run_promotion as crp


class TestAutonomousRunRejection:
    """Tests for autonomous run rejection functionality."""

    def test_autonomous_run_rejection_path(self, promotion_env):
        """Test that autonomous runs can be rejected."""
        result = crp.reject_run(promotion_env["run_id"], actor="tester", note="reject")

        assert result["decision"] == "rejected", \
            "Decision should be 'rejected'"
        assert result["actor"] == "tester", \
            "Actor should be recorded"
        assert result["note"] == "reject", \
            "Note should be recorded"

    def test_rejection_updates_run_status(self, promotion_env):
        """Test that rejection updates the run status to rejected."""
        crp.reject_run(promotion_env["run_id"], actor="tester", note="reject")

        runs = json.loads(
            (promotion_env["runs_root"] / "runs.json").read_text(encoding="utf-8")
        )
        
        assert runs[0]["status"] == "rejected", \
            "Run status should be updated to 'rejected'"

    def test_rejection_records_event(self, promotion_env):
        """Test that rejection records an event."""
        run_id = promotion_env["run_id"]
        crp.reject_run(run_id, actor="tester", note="test rejection")

        events_path = promotion_env["runs_root"] / "events.jsonl"
        assert events_path.exists(), "Events file should exist"

        events_content = events_path.read_text(encoding="utf-8")
        events = [json.loads(line) for line in events_content.strip().split("\n") if line]
        
        rejection_events = [e for e in events if e.get("type") == "approval.rejected"]
        assert len(rejection_events) > 0, \
            "Should have at least one rejection event"


class TestAutonomousRunIdempotency:
    """Tests for idempotent rejection handling."""

    def test_reject_already_rejected_is_idempotent(self, promotion_env):
        """Test that rejecting an already rejected run is idempotent."""
        run_id = promotion_env["run_id"]
        
        # First rejection
        result1 = crp.reject_run(run_id, actor="tester", note="first reject")
        assert result1["decision"] == "rejected"
        
        # Second rejection should return same result
        result2 = crp.reject_run(run_id, actor="tester", note="second reject")
        assert result2["decision"] == "rejected", \
            "Second rejection should succeed (idempotent)"

    def test_reject_updates_actor_on_repeated_rejection(self, promotion_env):
        """Test that repeated rejection updates the actor."""
        run_id = promotion_env["run_id"]
        
        crp.reject_run(run_id, actor="first_actor", note="first")
        crp.reject_run(run_id, actor="second_actor", note="second")

        approvals_path = promotion_env["runs_root"] / "approvals" / f"{run_id}.json"
        receipt = json.loads(approvals_path.read_text(encoding="utf-8"))
        
        assert receipt["actor"] == "second_actor", \
            "Latest rejection should update actor"


class TestAutonomousRunErrorScenarios:
    """Tests for error scenarios in autonomous run handling."""

    def test_reject_nonexistent_run_raises(self, promotion_env):
        """Test that rejecting a nonexistent run raises error."""
        with pytest.raises(crp.PromotionError, match="run not found"):
            crp.reject_run("nonexistent-run-id", actor="tester", note="test")

    def test_reject_applied_run_raises(self, promotion_env):
        """Test that rejecting an already applied run raises error."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        # First promote the run
        crp.promote_run(promotion_env["run_id"], actor="tester", note="promote")

        # Then try to reject it
        with pytest.raises(crp.PromotionError, match="already applied"):
            crp.reject_run(promotion_env["run_id"], actor="tester", note="try reject")

    def test_reject_run_with_invalid_status_raises(self, promotion_env):
        """Test that rejecting a run with invalid status raises error."""
        # Update run status to something that cannot be rejected
        runs = json.loads(
            (promotion_env["runs_root"] / "runs.json").read_text(encoding="utf-8")
        )
        runs[0]["status"] = "running"  # Cannot reject a run that is still running
        (promotion_env["runs_root"] / "runs.json").write_text(
            json.dumps(runs, indent=2), encoding="utf-8"
        )

        # Should raise because running is not a rejectable status
        with pytest.raises(crp.PromotionError, match="not awaiting approval"):
            crp.reject_run(promotion_env["run_id"], actor="tester", note="test")


class TestAutonomousRunApproval:
    """Tests for autonomous run approval flow."""

    def test_autonomous_run_can_be_promoted(self, promotion_env):
        """Test that autonomous runs can be promoted (approved)."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('autonomous update')\n", encoding="utf-8")

        result = crp.promote_run(promotion_env["run_id"], actor="tester", note="approve")

        assert result.status == "applied", \
            "Promotion should succeed"

    def test_promotion_updates_canonical_repo(self, promotion_env):
        """Test that promotion updates the canonical repository."""
        worktree = promotion_env["worktree"]
        new_content = "print('autonomous update')\n"
        (worktree / "app.py").write_text(new_content, encoding="utf-8")

        crp.promote_run(promotion_env["run_id"], actor="tester", note="approve")

        canonical_content = (promotion_env["canonical"] / "app.py").read_text(encoding="utf-8")
        assert "autonomous update" in canonical_content, \
            "Canonical repo should have promoted content"

    def test_promotion_records_receipt(self, promotion_env):
        """Test that promotion records a receipt."""
        worktree = promotion_env["worktree"]
        (worktree / "app.py").write_text("print('updated')\n", encoding="utf-8")

        result = crp.promote_run(promotion_env["run_id"], actor="tester", note="approve")

        assert result.receipt_path, "Should have receipt path"
        receipt = json.loads(
            open(result.receipt_path).read()
        )
        assert receipt["status"] == "applied", \
            "Receipt should show applied status"
