from __future__ import annotations
from pathlib import Path
from integration.worker_hardened.bridge import fallback_patch

def test_real_bug_fix(tmp_path):
    """Self-contained proof that the hardened worker's fallback can fix the bug.
    
    This test does not require the full code-agent-runtime to be importable,
    as it tests the strengthened top-level fallback logic directly.
    """
    repo = tmp_path / "repo"
    repo.mkdir()

    # 1. Create the buggy file
    f = repo / "parser.py"
    f.write_text("def first_token(tokens):\n    return tokens[0]\n", encoding="utf-8")

    # 2. Run the strengthened fallback from the bridge
    # The bridge logic targets 'first_token' and replaces 'return tokens[0]'
    res = fallback_patch([str(f)])

    # 3. Assert success
    assert res["success"] is True
    assert res["mode"] == "fallback"
    
    content = f.read_text(encoding="utf-8")
    assert "if tokens else None" in content
    assert "return tokens[0] if tokens else None" in content
