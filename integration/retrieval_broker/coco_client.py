from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path

from integration.shared_py.models import RetrievalRequest, RetrievalResult


def _coco_root() -> Path:
    value = os.environ.get('COCOINDEX_REPO_PATH')
    if not value:
        raise RuntimeError('COCOINDEX_REPO_PATH is not set')
    return Path(value).resolve()


def _load_modules(repo_path: Path):
    src_root = _coco_root() / 'src'
    if str(src_root) not in sys.path:
        sys.path.insert(0, str(src_root))

    os.environ['COCOINDEX_CODE_ROOT_PATH'] = str(repo_path)
    config_module = importlib.import_module('cocoindex_code.config')
    importlib.reload(config_module)
    query_module = importlib.import_module('cocoindex_code.query')
    importlib.reload(query_module)
    if not query_module.config.target_sqlite_db_path.exists():
        indexer_module = importlib.import_module('cocoindex_code.indexer')
        importlib.reload(indexer_module)
        return indexer_module, query_module
    return None, query_module


async def search_code(req: RetrievalRequest) -> list[RetrievalResult]:
    repo_path = Path(req.repo_path).resolve()
    indexer_module, query_module = _load_modules(repo_path)
    if req.refresh_index and indexer_module is not None:
        await indexer_module.app.update(report_to_stdout=False)

    rows = await query_module.query_codebase(
        query=req.query,
        limit=req.top_k,
        offset=0,
        languages=req.languages,
        paths=req.paths,
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
