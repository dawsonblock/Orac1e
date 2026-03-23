"""Patch executor for applying multi-file edit plans."""

import os
import tempfile
from pathlib import Path
from typing import Dict, Any, List


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

    for edit in edits:
        file_path = edit.get("file", "")
        search = edit.get("search", "")
        replace = edit.get("replace", "")

        if not file_path or not search:
            return {"success": False, "error": f"Invalid edit: missing file or search"}

        full_path = repo_path / file_path

        # Security: ensure file is within repo
        try:
            resolved = full_path.resolve()
            repo_resolved = repo_path.resolve()
            resolved.relative_to(repo_resolved)
        except ValueError:
            return {"success": False, "error": f"File outside repo: {file_path}"}

        if not full_path.exists():
            return {"success": False, "error": f"File not found: {file_path}"}

        try:
            content = full_path.read_text(encoding='utf-8')
        except (OSError, UnicodeDecodeError) as e:
            return {"success": False, "error": f"Cannot read {file_path}: {e}"}

        # Verify search exists
        if search not in content:
            return {"success": False, "error": f"Search text not found in {file_path}"}

        # Apply replacement
        new_content = content.replace(search, replace, 1)

        if new_content == content:
            return {"success": False, "error": f"No change made to {file_path}"}

        # Write atomically: create temp file in same directory, then rename
        try:
            temp_fd, temp_path = tempfile.mkstemp(
                dir=full_path.parent,
                prefix=f".{full_path.name}.tmp"
            )
            try:
                with os.fdopen(temp_fd, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                os.replace(temp_path, full_path)
                applied_files.append(file_path)
            except Exception:
                # Clean up temp file if rename failed
                try:
                    os.unlink(temp_path)
                except OSError:
                    pass
                raise
        except OSError as e:
            return {"success": False, "error": f"Cannot write {file_path}: {e}"}

    return {"success": True, "files": applied_files}
