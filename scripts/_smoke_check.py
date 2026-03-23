"""
Internal smoke-check script — run with .venv/bin/python scripts/_smoke_check.py
Validates all modules modified in the current implementation pass.
"""
import sys
import inspect
import tempfile
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

errors: list[str] = []


def ok(label: str) -> None:
    print(f"  [OK] {label}")


def fail(label: str, exc: Exception) -> None:
    errors.append(f"{label}: {exc}")
    print(f"  [FAIL] {label}: {exc}")


# ── 1. lifecycle ─────────────────────────────────────────────────────────────
try:
    from integration.lifecycle import (
        transition, VALID_TRANSITIONS, TERMINAL_STATES,
        TransitionError, is_terminal, assert_state,
    )
    # Walk every declared edge
    for src, targets in VALID_TRANSITIONS.items():
        for tgt in targets:
            r: dict = {"status": src}
            try:
                transition(r, tgt)
                assert r["status"] == tgt, f"{src}->{tgt}: status not updated"
            except TransitionError:
                errors.append(f"lifecycle: valid {src}->{tgt} raised TransitionError")
    # Terminal guard
    for s in list(TERMINAL_STATES):
        r = {"status": s}
        try:
            transition(r, "created")
            errors.append(f"lifecycle: terminal {s!r}->created should have raised")
        except TransitionError:
            pass
    # Idempotent
    r = {"status": "validating"}
    transition(r, "validating")
    assert r["status"] == "validating"
    ok("integration.lifecycle")
except Exception as e:
    fail("integration.lifecycle", e)


# ── 2. coding_run_promotion ──────────────────────────────────────────────────
try:
    from scripts.coding_run_promotion import (
        promote_run, reject_run, now_iso,
        _capture_patch_stats, PromotionError, PromotionResult,
    )
    # Verify _capture_patch_stats
    patch_text = (
        "--- a/src/foo.py\n+++ b/src/foo.py\n"
        "@@ -1,3 +1,3 @@\n def f():\n-    return None\n+    return 42\n"
        "--- a/src/bar.py\n+++ b/src/bar.py\n"
        "@@ -1,2 +1,3 @@\n x = 1\n+y = 2\n"
    )
    with tempfile.NamedTemporaryFile(mode="w", suffix=".patch", delete=False) as f:
        f.write(patch_text)
        tmp = Path(f.name)
    try:
        files, added, removed = _capture_patch_stats(tmp)
        assert files == ["src/foo.py", "src/bar.py"], f"files={files}"
        assert added == 2, f"added={added}"
        assert removed == 1, f"removed={removed}"
    finally:
        tmp.unlink(missing_ok=True)
    # Verify transition is imported and wired (not a bare assignment)
    import ast, textwrap
    src_text = (ROOT / "scripts" / "coding_run_promotion.py").read_text()
    assert "from integration.lifecycle import transition" in src_text
    assert 'run["status"] = "applied"' not in src_text, "bare mutation still present"
    assert 'run["status"] = "failed"' not in src_text, "bare mutation still present"
    assert 'run["status"] = "rejected"' not in src_text, "bare mutation still present"
    ok("scripts.coding_run_promotion")
except Exception as e:
    fail("scripts.coding_run_promotion", e)


# ── 3. serve_coding_runs ────────────────────────────────────────────────────
try:
    import importlib
    scr = importlib.import_module("scripts.serve_coding_runs")
    assert hasattr(scr, "app"), "app attribute missing"
    ok("scripts.serve_coding_runs")
except Exception as e:
    fail("scripts.serve_coding_runs", e)


# ── 4. result_mapper ─────────────────────────────────────────────────────────
try:
    from integration.worker_hardened.result_mapper import to_response
    sig = inspect.signature(to_response)
    assert "failure_reason" in sig.parameters, "failure_reason param missing"
    # Call with all-None args (no runtime deps needed)
    resp = to_response(None, None, type("T", (), {"attempted_files": [], "rejected_files": [], "reasons": [], "strategies": []})(), None, failure_reason="no_patch_produced")
    assert resp["failure_reason"] == "no_patch_produced"
    assert resp["diff"] == ""
    ok("integration.worker_hardened.result_mapper")
except Exception as e:
    fail("integration.worker_hardened.result_mapper", e)


# ── 5. bridge ────────────────────────────────────────────────────────────────
try:
    from integration.worker_hardened.bridge import _task_normalize, _heuristic_fallback
    from integration.shared_py.models import Constraints

    class _FakeReq:
        run_id = "test-run"
        task = "fix get_first_token so it does not return None for empty list"
        repo_path = str(ROOT)
        constraints = Constraints(allowed_paths=["src/"], max_changed_lines=500)

    hints = _task_normalize(_FakeReq())  # type: ignore
    assert any("get_first_token" in t for t, _ in hints), f"expected hint for get_first_token, got {hints}"
    assert any("return None" in t for t, _ in hints), f"expected return-None hint, got {hints}"
    ok("integration.worker_hardened.bridge (_task_normalize)")
except Exception as e:
    fail("integration.worker_hardened.bridge", e)


# ── 6. preflight ─────────────────────────────────────────────────────────────
try:
    from integration.preflight import _service_enabled, _load_system_config
    # Should not raise
    cfg = _load_system_config()
    assert isinstance(cfg, dict)
    # Both workers should be enabled per default system.yaml
    assert _service_enabled("workers", "aider") is True
    assert _service_enabled("workers", "hardened") is True
    ok("integration.preflight")
except Exception as e:
    fail("integration.preflight", e)


# ── 7. diff_utils ────────────────────────────────────────────────────────────
try:
    from integration.shared_py.diff_utils import enforce_path_budget, BLOCKED_PATH_PREFIXES

    # diff_utils: enforce_path_budget correct semantics
    # 1) fail-closed: empty allowlist flags all files
    violations_empty = enforce_path_budget(
        "--- a/foo.py\n+++ b/foo.py\n+x\n", []
    )
    assert violations_empty != [], "empty allowlist should flag files (fail-closed)"

    # 2) path outside allowed_prefixes is a violation
    violations_outside = enforce_path_budget(
        "--- a/src/foo.py\n+++ b/src/foo.py\n+x\n", ["tests/"]
    )
    assert violations_outside != [], "path outside allowed_prefixes should be a violation"

    # 3) is_path_blocked catches BLOCKED_PATH_PREFIXES even when the path
    #    would otherwise be in the allowed list
    blocked_diff = (
        "--- a/.github/workflows/ci.yml\n"
        "+++ b/.github/workflows/ci.yml\n+x\n"
    )
    violations_blocked = enforce_path_budget(blocked_diff, [".github/"])
    assert violations_blocked != [], (
        f"is_path_blocked should catch .github/ even when 'allowed': {violations_blocked}"
    )
    ok("integration.shared_py.diff_utils")
except Exception as e:
    fail("integration.shared_py.diff_utils", e)


# ── 8. pyproject.toml exists ─────────────────────────────────────────────────
try:
    pyproj = ROOT / "pyproject.toml"
    assert pyproj.exists(), "pyproject.toml missing"
    content = pyproj.read_text()
    assert "oracle-system" in content
    assert "oracle-preflight" in content
    assert "oracle-run-server" in content
    assert '"fastapi"' in content
    assert '"gitpython"' in content
    ok("pyproject.toml")
except Exception as e:
    fail("pyproject.toml", e)


# ── 9. requirements.txt has new deps ─────────────────────────────────────────
try:
    reqs = (ROOT / "requirements.txt").read_text()
    assert "shtab" in reqs, "shtab missing from requirements.txt"
    assert "httpx" in reqs, "httpx missing from requirements.txt"
    assert "git+https://github.com/dawsonblock/Orac1e.git" not in reqs, "git editable installs should be local paths"
    assert "-e third_party/code-agent-runtime" in reqs, "local code-agent-runtime editable install missing"
    assert "-e third_party/cocoindex-code" in reqs, "local cocoindex editable install missing"
    assert "-e ." in reqs, "local root editable install missing"
    ok("requirements.txt")
except Exception as e:
    fail("requirements.txt", e)


# ── 10. smoke_simulated.sh exists; smoke_e2e.sh gone ───────────────────────
try:
    assert (ROOT / "scripts" / "smoke_simulated.sh").exists(), "smoke_simulated.sh missing"
    assert not (ROOT / "scripts" / "smoke_e2e.sh").exists(), "smoke_e2e.sh still present (should be renamed)"
    ok("scripts/smoke_simulated.sh (rename)")
except Exception as e:
    fail("smoke_simulated.sh rename", e)


# ── 11. bootstrap_all.sh has import assertions + receipt ───────────────────
try:
    bs = (ROOT / "scripts" / "bootstrap_all.sh").read_text()
    assert "source .venv/bin/activate" in bs, "venv activation missing"
    assert "pip install -r requirements.txt" in bs, "requirements install missing"
    assert "pip install -e ." in bs, "root editable install missing"
    assert "pip install -e third_party/aider" in bs, "aider editable install missing"
    assert "pip install -e third_party/code-agent-runtime" in bs, "code-agent-runtime editable install missing"
    assert "pip install -e third_party/cocoindex-code" in bs, "cocoindex editable install missing"
    assert "Import checks passed" in bs, "import verification missing"
    assert "PYTHONPATH" not in bs, "bootstrap should not rely on PYTHONPATH"
    assert "requirements_bootstrap.txt" not in bs, "bootstrap should not generate requirements_bootstrap.txt"
    ok("scripts/bootstrap_all.sh")
except Exception as e:
    fail("scripts/bootstrap_all.sh", e)


# ── Summary ─────────────────────────────────────────────────────────────────
print()
if errors:
    print(f"FAILED — {len(errors)} error(s):")
    for err in errors:
        print(f"  • {err}")
    sys.exit(1)
else:
    print("All checks passed ✓")
