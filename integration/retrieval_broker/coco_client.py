from __future__ import annotations

import asyncio
import importlib
import os
import sys
from pathlib import Path
from typing import Any

from integration.shared_py.models import RetrievalRequest, RetrievalResult

# Per-repo-path module cache: { repo_path_str: (config_module, query_module, indexer_module | None) }
_MODULE_CACHE: dict[str, tuple[Any, Any, Any]] = {}

# Global lock serialises module-loading and env-var mutation so concurrent
# requests to different repos cannot clobber each other's COCOINDEX_CODE_ROOT_PATH.
_LOAD_LOCK: asyncio.Lock | None = None


def _get_load_lock() -> asyncio.Lock:
    """Return the process-wide asyncio lock, creating it lazily inside the event loop."""
    global _LOAD_LOCK
    if _LOAD_LOCK is None:
        _LOAD_LOCK = asyncio.Lock()
    return _LOAD_LOCK


def _coco_root() -> Path:
    value = os.environ.get('COCOINDEX_REPO_PATH')
    if not value:
        raise RuntimeError('COCOINDEX_REPO_PATH is not set')
    return Path(value).resolve()


def _load_modules_sync(repo_path: Path) -> tuple[Any, Any, Any]:
    """Load (and cache) cocoindex modules for *repo_path*.

    Must be called while the caller holds *_LOAD_LOCK* so that the global
    os.environ mutation is never observed by another concurrent request.

    Returns (config_module, query_module, indexer_module | None).
    """
    key = str(repo_path)
    if key in _MODULE_CACHE:
        return _MODULE_CACHE[key]

    src_root = _coco_root() / 'src'
    if str(src_root) not in sys.path:
        sys.path.insert(0, str(src_root))

    # Mutate env only while the lock is held.
    os.environ['COCOINDEX_CODE_ROOT_PATH'] = key

    config_module = importlib.import_module('cocoindex_code.config')
    importlib.reload(config_module)
    query_module = importlib.import_module('cocoindex_code.query')
    importlib.reload(query_module)

    indexer_module: Any = None
    if not query_module.config.target_sqlite_db_path.exists():
        indexer_module = importlib.import_module('cocoindex_code.indexer')
        importlib.reload(indexer_module)

    _MODULE_CACHE[key] = (config_module, query_module, indexer_module)
    return config_module, query_module, indexer_module


async def search_code(req: RetrievalRequest) -> list[RetrievalResult]:
    repo_path = Path(req.repo_path).resolve()

    async with _get_load_lock():
        _config_module, query_module, indexer_module = _load_modules_sync(repo_path)

        # If caller requests a fresh index, rebuild it while still holding the
        # lock so no other request queries a half-built index.
        if req.refresh_index and indexer_module is not None:
            await asyncio.wait_for(
                indexer_module.app.update(report_to_stdout=False),
                timeout=300,
            )

    rows = await asyncio.wait_for(
        query_module.query_codebase(
            query=req.query,
            limit=req.top_k,
            offset=0,
            languages=req.languages,
            paths=req.paths,
        ),
        timeout=30,
    )
    return [
        RetrievalResult(
            path=row.file_path,
            score=row.score,
            snippet=row.content,
            start_line=row.start_line,
            end_line=row.end_line,
            language=row.language,
        )
        for row in rows
    ]
