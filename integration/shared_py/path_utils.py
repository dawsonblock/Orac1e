from __future__ import annotations
from pathlib import PurePosixPath

def normalize_rel_path(path: str) -> str:
    p = PurePosixPath(path)
    if p.is_absolute():
        raise ValueError("absolute paths are not allowed")
    normalized = str(p)
    if ".." in p.parts:
        raise ValueError("path traversal is not allowed")
    return normalized

def path_allowed(path: str, allowed_prefixes: list[str]) -> bool:
    if not allowed_prefixes:
        return True
    normalized = normalize_rel_path(path)
    return any(normalized.startswith(prefix) for prefix in allowed_prefixes)
