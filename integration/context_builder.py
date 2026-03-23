"""Context builder for gathering relevant files from a repository."""

import os
from pathlib import Path
from typing import List, Dict, Any


def build_context(repo: str, max_files: int = 8, max_chars_per_file: int = 2000) -> List[Dict[str, Any]]:
    """
    Build context by gathering Python files from the repository.

    Args:
        repo: Path to the repository root
        max_files: Maximum number of files to include in context
        max_chars_per_file: Maximum characters to read from each file

    Returns:
        List of dicts with 'file' and 'content' keys
    """
    repo_path = Path(repo)
    files = []

    # Walk the repo for Python files
    for root, _, filenames in os.walk(repo_path):
        # Skip hidden and cache directories
        if any(part.startswith('.') for part in Path(root).parts):
            continue
        if '__pycache__' in root:
            continue

        for f in filenames:
            if f.endswith('.py'):
                full_path = os.path.join(root, f)
                rel_path = os.path.relpath(full_path, repo_path)
                files.append(rel_path)

    # Sort for determinism, take first max_files
    selected = sorted(files)[:max_files]

    context = []
    for f in selected:
        path = repo_path / f
        try:
            content = path.read_text(encoding='utf-8', errors='replace')
            # Truncate if needed
            if len(content) > max_chars_per_file:
                content = content[:max_chars_per_file] + '\n... [truncated]'
            context.append({'file': f, 'content': content})
        except (OSError, UnicodeDecodeError):
            # Skip files we can't read
            continue

    return context
