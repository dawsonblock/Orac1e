from runtime.intake.issue_parser import IssueParser


def test_issue_parser_extracts_file_replace_with_and_tests():
    body = """
    File: src/calc.py
    Replace: return x + 2
    With: return x + 1
    Tests: tests/test_calc.py, tests/test_more.py
    """
    parsed = IssueParser().parse('Fix calc', body)
    assert parsed.explicit_files == ['src/calc.py']
    assert parsed.replace_text == 'return x + 2'
    assert parsed.with_text == 'return x + 1'
    assert parsed.tests == ['tests/test_calc.py', 'tests/test_more.py']
