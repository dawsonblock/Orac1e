from __future__ import annotations

from runtime.common.result import Result
from runtime.events.schemas import PatchArtifact


class PatchGuard:
    def __init__(self, max_changed_files: int = 12, max_changed_lines: int = 200):
        self.max_changed_files = max_changed_files
        self.max_changed_lines = max_changed_lines
        self.forbidden_prefixes = [".github/workflows/", "infra/", "deploy/", "secrets/"]
        self.blocked_suffixes = ['.lock']

    def evaluate(self, artifact: PatchArtifact) -> Result:
        if len(artifact.changed_files) > self.max_changed_files:
            return Result(False, "too_many_files", "patch changes too many files")
        if any(any(path.startswith(prefix) for prefix in self.forbidden_prefixes) for path in artifact.changed_files):
            return Result(False, "forbidden_path", "patch changes forbidden paths")
        if any(path.endswith(tuple(self.blocked_suffixes)) for path in artifact.changed_files):
            return Result(False, 'blocked_suffix', 'patch changes blocked lockfile-like paths')
        if not artifact.diff_text.strip():
            return Result(False, "empty_diff", "patch diff is empty")

        added = 0
        removed = 0
        removed_asserts = 0
        added_asserts = 0
        for line in artifact.diff_text.splitlines():
            if line.startswith('+++') or line.startswith('---') or line.startswith('@@'):
                continue
            if line.startswith('+'):
                added += 1
                if 'assert' in line:
                    added_asserts += 1
            elif line.startswith('-'):
                removed += 1
                if 'assert' in line:
                    removed_asserts += 1
        if added + removed > self.max_changed_lines:
            return Result(False, 'too_many_changed_lines', 'patch changes too many lines')
        if removed_asserts > 0 and added_asserts == 0:
            return Result(False, 'assertions_removed', 'patch removes assertions without adding replacements')
        return Result(True, "ok", "patch accepted by guard")
