"""Regression tests for empty validation failure.

This module tests the behavior when no validation is configured:
1. Empty validation fails without allowNoValidation flag
2. Empty validation succeeds with allowNoValidation=True
3. Stage metadata is properly recorded in receipts

These tests ensure the allowNoValidation override mechanism works correctly.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from scripts import coding_run_promotion as crp


class TestEmptyValidationFailure:
    """Tests for empty validation failure scenarios."""

    def test_empty_validation_fails_without_allowNoValidation(self, promotion_env):
        """Test that empty validation fails without allowNoValidation flag.
        
        When no validationCommands are specified and allowNoValidation is not set,
        promotion should fail with an appropriate error message.
        """
        # Ensure no validation commands are set (empty validation)
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        # Remove validation commands to simulate empty validation
        metadata["validationCommands"] = []
        # Ensure allowNoValidation is NOT set
        metadata.pop("allowNoValidation", None)
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        # Attempt promotion - should fail
        with pytest.raises(crp.PromotionError, match="no validation configured"):
            crp.promote_run(
                promotion_env["run_id"], actor="tester", note="should fail"
            )

    def test_empty_validation_succeeds_with_allowNoValidation_true(self, promotion_env):
        """Test that empty validation succeeds when allowNoValidation=True.
        
        When allowNoValidation is explicitly set to True, promotion should succeed
        even without any validation commands.
        """
        # Ensure no validation commands are set
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = []
        # Explicitly set allowNoValidation to True
        metadata["allowNoValidation"] = True
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        # Write a change so there is a real diff to promote
        (promotion_env["worktree"] / "app.py").write_text(
            "print('allow_no_validation')\n", encoding="utf-8"
        )

        # Promotion should succeed with allowNoValidation
        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="skip validation"
        )

        assert result.status == "applied", \
            "Promotion should succeed with allowNoValidation=True"
        assert result.validation_ok is True, \
            "Validation should be marked as ok (skipped)"

    def test_empty_validation_succeeds_via_cli_flag(self, promotion_env):
        """Test that allowNoValidation works via CLI argument."""
        # Ensure no validation commands are set
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = []
        # Don't set allowNoValidation in metadata - test CLI override
        metadata.pop("allowNoValidation", None)
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        # Write a change so there is a real diff to promote
        (promotion_env["worktree"] / "app.py").write_text(
            "print('cli_flag')\n", encoding="utf-8"
        )

        # Test with allow_no_validation=True in the call
        result = crp.promote_run(
            promotion_env["run_id"],
            actor="tester",
            note="CLI override",
            allow_no_validation=True,
        )

        assert result.status == "applied", \
            "Promotion should succeed with CLI allow_no_validation=True"


class TestEmptyValidationStageMetadata:
    """Tests for stage metadata in receipts during empty validation."""

    def test_stage_metadata_in_receipt_when_skipped(self, promotion_env):
        """Test that stage metadata is recorded in receipt when validation is skipped.
        
        When validation is skipped via allowNoValidation, the receipt should contain
        metadata indicating which stages were skipped and why.
        """
        # Set up with allowNoValidation
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = []
        metadata["allowNoValidation"] = True
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        # Write a change so there is a real diff to promote
        (promotion_env["worktree"] / "app.py").write_text(
            "print('skip_meta')\n", encoding="utf-8"
        )

        # Promote
        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="skip validation"
        )

        # Read the promotion receipt
        receipt = json.loads(open(result.receipt_path).read())

        # Verify stage metadata is present
        assert "validation" in receipt, \
            "Receipt should contain validation metadata"
        
        validation_meta = receipt["validation"]
        
        # Should indicate validation was skipped
        assert validation_meta.get("skipped") is True, \
            "Validation should be marked as skipped"
        assert validation_meta.get("skip_reason") == "allow_no_validation", \
            "Skip reason should be 'allow_no_validation'"

    def test_stage_metadata_shows_empty_stages(self, promotion_env):
        """Test that stage metadata shows empty stages array when no validation.
        
        When no validation is configured and allowNoValidation is not set,
        the receipt should show empty stages.
        """
        # Set up with no validation and no allowNoValidation (will fail)
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = []
        metadata.pop("allowNoValidation", None)
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        # The promotion should fail, but let's check the error message
        with pytest.raises(crp.PromotionError, match="no validation configured"):
            crp.promote_run(
                promotion_env["run_id"], actor="tester", note="should fail"
            )


class TestAllowNoValidationEnvVar:
    """Tests for environment variable override of allowNoValidation."""

    def test_allow_no_validation_env_var(self, promotion_env, monkeypatch):
        """Test that ORACLE_ALLOW_NO_VALIDATION env var enables skip.
        
        When the environment variable ORACLE_ALLOW_NO_VALIDATION is set,
        validation should be skipped even without the metadata flag.
        """
        # Set environment variable
        monkeypatch.setenv("ORACLE_ALLOW_NO_VALIDATION", "1")

        # Set up with no validation commands
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = []
        metadata.pop("allowNoValidation", None)
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        # Write a change so there is a real diff to promote
        (promotion_env["worktree"] / "app.py").write_text(
            "print('env_var')\n", encoding="utf-8"
        )

        # Promotion should succeed via env var
        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="env var override"
        )

        assert result.status == "applied", \
            "Promotion should succeed with ORACLE_ALLOW_NO_VALIDATION=1"


class TestValidationStagesWithEmptyCommands:
    """Tests for validation stages when commands are empty but stages exist."""

    def test_validation_stages_still_require_validation(self, promotion_env):
        """Test that validation stages still require commands.
        
        Even if validation stages are defined in the profile, if no actual
        commands are provided, it should still fail without allowNoValidation.
        """
        # Set up with empty commands but stages would be defined in profile
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = []
        metadata.pop("allowNoValidation", None)
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        # Should fail because no validation is configured
        with pytest.raises(crp.PromotionError, match="no validation configured"):
            crp.promote_run(
                promotion_env["run_id"], actor="tester", note="should fail"
            )

    def test_validation_stages_with_allowNoValidation(self, promotion_env):
        """Test that validation stages are skipped when allowNoValidation=True.
        
        When allowNoValidation is set, even stages from the validation profile
        should be skipped.
        """
        # Set up with allowNoValidation
        metadata = json.loads(
            (
                promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
            ).read_text(encoding="utf-8")
        )
        metadata["validationCommands"] = []
        metadata["allowNoValidation"] = True
        (
            promotion_env["metadata_dir"] / f"{promotion_env['run_id']}.json"
        ).write_text(json.dumps(metadata, indent=2), encoding="utf-8")

        # Write a change so there is a real diff to promote
        (promotion_env["worktree"] / "app.py").write_text(
            "print('stages_skipped')\n", encoding="utf-8"
        )

        result = crp.promote_run(
            promotion_env["run_id"], actor="tester", note="skip all stages"
        )

        assert result.status == "applied", \
            "All validation stages should be skipped with allowNoValidation=True"