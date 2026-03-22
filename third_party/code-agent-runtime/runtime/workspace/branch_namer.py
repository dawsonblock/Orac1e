from __future__ import annotations


def branch_name(issue_number: int, attempt_index: int) -> str:
    return f"agent/issue-{issue_number}-attempt-{attempt_index:02d}"
