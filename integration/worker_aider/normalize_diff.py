from __future__ import annotations

from integration.shared_py.diff_utils import changed_line_count, enforce_path_budget, extract_touched_files


def normalize_diff(diff_text: str, allowed_paths: list[str], max_changed_lines: int) -> tuple[str, list[str], list[str]]:
    warnings: list[str] = []
    touched = extract_touched_files(diff_text)
    violations = enforce_path_budget(diff_text, allowed_paths)
    if violations:
        raise ValueError(f"diff touched blocked paths: {', '.join(violations)}")
    changed = changed_line_count(diff_text)
    if changed > max_changed_lines:
        raise ValueError(f'diff exceeded max_changed_lines: {changed} > {max_changed_lines}')
    if not touched:
        warnings.append('Aider returned an empty diff.')
    return diff_text, touched, warnings
