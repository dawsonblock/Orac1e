"""Patch executor for applying multi-file edit plans."""

import os
import tempfile
from pathlib import Path
from typing import Dict, Any, List


def _write_text_atomic(full_path: Path, content: str) -> None:
    temp_fd, temp_path = tempfile.mkstemp(
        dir=full_path.parent,
        prefix=f".{full_path.name}.tmp"
    )
    try:
        with os.fdopen(temp_fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(temp_path, full_path)
    except Exception:
        try:
            os.close(temp_fd)
        except OSError:
            pass
        try:
            os.unlink(temp_path)
        except OSError:
            pass
        raise


def _rollback_changes(repo_path: Path, applied_files: List[str], original_contents: Dict[str, str]) -> List[str]:
    """Restore files to original state. Returns list of files that failed to restore."""
    restored = set()
    failed = []
    for file_path in reversed(applied_files):
        if file_path in restored or file_path not in original_contents:
            continue
        try:
            _write_text_atomic(repo_path / file_path, original_contents[file_path])
            restored.add(file_path)
        except Exception as e:
            failed.append(f"{file_path}: {e}")
    return failed


def apply_plan(plan: Dict[str, Any], repo: str) -> Dict[str, Any]:
    """
    Apply an edit plan to the repository.

    Args:
        plan: Dict with 'edits' list, each with 'file', 'search', 'replace'
        repo: Path to repository root

    Returns:
        Dict with 'success' boolean
    """
    repo_path = Path(repo)
    edits = plan.get("edits", [])

    if not edits:
        return {"success": False, "error": "No edits in plan"}

    applied_files = []
    original_contents: Dict[str, str] = {}

    def fail(error: str) -> Dict[str, Any]:
        if applied_files:
            failed = _rollback_changes(repo_path, applied_files, original_contents)
            if failed:
                return {"success": False, "error": f"{error}; rollback failed for: {', '.join(failed)}"}
        return {"success": False, "error": error}

    for edit in edits:
        file_path = edit.get("file", "")
        search = edit.get("search", "")
        replace = edit.get("replace", "")

        if not file_path or not search:
            return fail("Invalid edit: missing file or search")

        full_path = repo_path / file_path

        # Security: ensure file is within repo and not a symlink
        if full_path.is_symlink():
            return fail(f"Symlinks not allowed: {file_path}")

        try:
            resolved = full_path.resolve()
            repo_resolved = repo_path.resolve()
            resolved.relative_to(repo_resolved)
        except ValueError:
            return fail(f"File outside repo: {file_path}")

        if not full_path.exists():
            return fail(f"File not found: {file_path}")

        try:
            content = full_path.read_text(encoding='utf-8')
        except (OSError, UnicodeDecodeError) as e:
            return fail(f"Cannot read {file_path}: {e}")

        if file_path not in original_contents:
            original_contents[file_path] = content

        # Verify search text exists in the content
        if search not in content:
            return fail(f"Search text not found in {file_path}")

        # Apply replacement
        new_content = content.replace(search, replace, 1)

        if new_content == content:
            return fail(f"No change made to {file_path}")

        try:
            _write_text_atomic(full_path, new_content)
            applied_files.append(file_path)
        except OSError as e:
            return fail(f"Cannot write {file_path}: {e}")

    return {"success": True, "files": applied_files}
