from __future__ import annotations

from integration.shared_py.models import RetrievalResult


def sort_results(items: list[RetrievalResult]) -> list[RetrievalResult]:
    return sorted(items, key=lambda item: item.score, reverse=True)
