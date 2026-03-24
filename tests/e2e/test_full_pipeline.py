"""End-to-end test for the full execution pipeline."""

from integration.pipeline import run_pipeline


def test_full_pipeline(tmp_path, monkeypatch):
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

    def fake_create_plan(task, context):
        # Return a wrong plan initially to test the failure analysis path
        return {
            "edits": [
                {
                    "file": "parser.py",
                    "search": "def first_token(tokens):\n    return tokens[0]\n",
                    "replace": "def first_token(tokens):\n    return tokens[0]  # wrong fix\n"
                }
            ]
        }

    call_count = 0
    def fake_analyze_failure(task, error_output, context):
        nonlocal call_count
        call_count += 1
        # Return the correct fix plan on failure analysis
        if call_count == 1:
            return {
                "edits": [
                    {
                        "file": "parser.py",
                        "search": "def first_token(tokens):\n    return tokens[0]  # wrong fix\n",
                        "replace": "def first_token(tokens):\n    if not tokens:\n        return None\n    return tokens[0]\n"
                    }
                ]
            }
        return None

    monkeypatch.setattr("integration.pipeline.create_plan", fake_create_plan)
    monkeypatch.setattr("integration.pipeline.analyze_failure", fake_analyze_failure)

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
    assert "if not tokens:" in parser_content and "return None" in parser_content
