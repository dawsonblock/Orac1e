from __future__ import annotations

import re
from pathlib import PurePosixPath
from typing import Optional

_DIFF_GIT_RE = re.compile(r'^diff --git a/(.+?) b/(.+?)$', re.MULTILINE)
_PLUS_PLUS_RE = re.compile(r'^\+\+\+ b/(.+)$', re.MULTILINE)
_BINARY_RE = re.compile(r'^Binary files (.+) and (.+) differ$', re.MULTILINE)

BLOCKED_PATH_PREFIXES = [
    ".git/",
    ".github/workflows/",
    "secrets/",
    "infra/production/",
    "deploy/",
]


def extract_touched_files(diff_text: str) -> list[str]:
    paths: list[str] = []

    for match in _DIFF_GIT_RE.finditer(diff_text):
        b_path = match.group(2)
        if b_path and b_path != "/dev/null":
            paths.append(b_path)

    for match in _PLUS_PLUS_RE.finditer(diff_text):
        path = match.group(1)
        if path and path != "/dev/null":
            if path not in paths:
                paths.append(path)

    lines = diff_text.splitlines()
    for i, line in enumerate(lines):
        if _BINARY_RE.match(line):
            if i > 0:
                prev_line = lines[i - 1]
                git_match = re.match(r'^diff --git a/(.+?) b/(.+?)$', prev_line)
                if git_match:
                    b_path = git_match.group(2)
                    if b_path and b_path not in paths:
                        paths.append(b_path)

    return sorted(set(paths))


def normalize_repo_path(path: str) -> Optional[str]:
    normalized = path.replace("\\", "/")
    normalized = re.sub(r"/+", "/", normalized)
    normalized = normalized.lstrip("./")

    if not normalized or normalized == ".":
        return None

    if normalized.startswith("/"):
        return None

    try:
        pure = PurePosixPath(normalized)
        resolved = str(pure)
        if resolved.startswith(".."):
            return None
    except Exception:
        return None

    return resolved


def check_path_traversal(path: str) -> bool:
    normalized = normalize_repo_path(path)
    if normalized is None:
        return True

    try:
        pure = PurePosixPath(normalized)
    except Exception:
        # Conservatively treat unexpected path parsing issues as traversal.
        return True

    return ".." in pure.parts
def is_path_blocked(path: str) -> bool:
    normalized = normalize_repo_path(path)
    if normalized is None:
        return True

    for blocked in BLOCKED_PATH_PREFIXES:
        base = blocked.rstrip("/")
        if normalized == base or normalized.startswith(base + "/"):
            return True
    return False


def changed_line_count(diff_text: str) -> int:
    count = 0
    for line in diff_text.splitlines():
        if line.startswith('+++') or line.startswith('---'):
            continue
        if line.startswith('+') or line.startswith('-'):
            count += 1
    return count


def enforce_path_budget(diff_text: str, allowed_prefixes: list[str]) -> list[str]:
    if not allowed_prefixes:
        return []

    violations: list[str] = []
    normalized_prefixes = [prefix.replace('\\', '/').lstrip('./') for prefix in allowed_prefixes]

    for path in extract_touched_files(diff_text):
        norm = normalize_repo_path(path)
        if norm is None:
            violations.append(path)
            continue

        if check_path_traversal(path):
            violations.append(path)
            continue

        if is_path_blocked(path):
            violations.append(path)
            continue

        if not any(norm.startswith(prefix) for prefix in normalized_prefixes):
            violations.append(path)

    return violations
