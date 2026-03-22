from runtime.intake.issue_parser import IssueParser


def test_issue_parser_supports_regex_and_test_blocks():
    body = """
File: src/calc.py
Regex: return x \\+ 2
With: return x + 1
Add-Test-File: tests/test_calc.py
Add-Test-Content: ```python
def test_again():
    assert True
```
"""
    parsed = IssueParser().parse('Fix calc', body)
    assert parsed.regex_pattern == r'return x \+ 2'
    assert parsed.with_text == 'return x + 1'
    assert parsed.add_test_file == 'tests/test_calc.py'
    assert 'def test_again()' in (parsed.add_test_content or '')
