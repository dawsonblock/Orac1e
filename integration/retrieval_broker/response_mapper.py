from __future__ import annotations

def normalize_results(results: list[dict]) -> list[dict]:
    normalized = []
    for item in results:
        normalized.append({
            "path": item.get("path", ""),
            "score": float(item.get("score", 0.0)),
            "snippet": item.get("snippet", "")
        })
    return normalized
