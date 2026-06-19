from __future__ import annotations

def build_query(task: str) -> str:
    return " ".join(task.strip().split())
