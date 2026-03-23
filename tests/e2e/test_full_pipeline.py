"""End-to-end test for the full execution pipeline."""

import pytest
from integration.pipeline import run_pipeline


def test_full_pipeline(tmp_path):
    """
    Test the full pipeline: task → worker → patch → validation → apply.

    Creates a temporary repo with a buggy function and a failing test,
    then verifies the pipeline fixes it.
    """
    repo = tmp_path / "repo"
    repo.mkdir()

    # Create the buggy parser module
    (repo / "parser.py").write_text(
        "def first_token(tokens):\n"
        "    return tokens[0]\n"
    )

    # Create the failing test
    (repo / "test_parser.py").write_text(
        "from parser import first_token\n\n"
        "def test_empty():\n"
        "    assert first_token([]) is None\n\n"
        "def test_nonempty():\n"
        "    assert first_token([1, 2, 3]) == 1\n"
    )

    # Run the pipeline
    result = run_pipeline(
        "fix first_token so empty list returns None",
        str(repo)
    )

    # Verify the result
    assert result["status"] == "applied", f"Expected 'applied' but got: {result}"
    assert result["attempts"] >= 1

    # Verify the fix was actually applied
    parser_content = (repo / "parser.py").read_text()
    assert "if not tokens" in parser_content or "return None" in parser_content
