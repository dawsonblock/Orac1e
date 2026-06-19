from runtime.intake.issue_parser import IssueParser


def test_issue_parser_extracts_stacktrace_files_and_controls():
    body = '''
Traceback (most recent call last):
  File "src/calc.py", line 10, in add
    return x + 2
Ignore-Files: tests/test_calc.py, docs/readme.md
Search: overflow, boundary case
Symbol: add, clamp_value
Max-Files: 7
Max-Attempts: 3
'''
    parsed = IssueParser().parse('Fix add', body)
    assert 'src/calc.py' in parsed.stacktrace_files
    assert 'src/calc.py' in parsed.explicit_files
    assert parsed.ignored_files == ['tests/test_calc.py', 'docs/readme.md']
    assert parsed.search_terms == ['overflow', 'boundary case']
    assert parsed.symbol_names == ['add', 'clamp_value']
    assert parsed.max_files == 7
    assert parsed.max_attempts == 3
