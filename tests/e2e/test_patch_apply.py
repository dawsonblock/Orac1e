from __future__ import annotations

import json
import subprocess

import pytest

from scripts import coding_run_promotion as crp


def test_patch_apply_validation_failure_rolls_back(promotion_env):
    worktree = promotion_env["worktree"]
    (worktree / "app.py").write_text("print('broken'\n", encoding="utf-8")

    with pytest.raises(crp.PromotionError):
        crp.promote_run(promotion_env["run_id"], actor="tester")

    assert "hello" in (promotion_env["canonical"] / "app.py").read_text(encoding="utf-8")
    status = json.loads((promotion_env["runs_root"] / "runs.json").read_text(encoding="utf-8"))[0]["status"]
    assert status == "failed"
    git_status = subprocess.run(
        ["git", "-C", str(promotion_env["canonical"]), "status", "--porcelain"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    assert git_status == ""
