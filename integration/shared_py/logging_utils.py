"""Structured logging utilities.

All services and workers should use ``emit()`` for operational events so that
log output is machine-parseable JSON on stderr.  ``get_logger()`` is kept for
backward compatibility with existing callers that use the stdlib logger.
"""
from __future__ import annotations

import json
import logging
import sys
from datetime import datetime, timezone
from typing import Any


def _iso_now() -> str:
    return (
        datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def emit(
    stage: str,
    status: str,
    *,
    run_id: str | None = None,
    worker: str | None = None,
    error: str | None = None,
    **extra: Any,
) -> None:
    """Write a single structured JSON log line to stderr.

    Args:
        stage:   The pipeline stage name, e.g. ``"propose"``, ``"validate"``.
        status:  Short status string, e.g. ``"start"``, ``"success"``, ``"failed"``.
        run_id:  Optional coding run ID for correlation.
        worker:  Optional worker identifier, e.g. ``"hardened"``, ``"aider"``.
        error:   Optional error message for failure events.
        **extra: Additional key/value pairs merged into the log record.
    """
    record: dict[str, Any] = {
        "ts": _iso_now(),
        "stage": stage,
        "status": status,
    }
    if run_id is not None:
        record["run_id"] = run_id
    if worker is not None:
        record["worker"] = worker
    if error is not None:
        record["error"] = error
    record.update(extra)
    sys.stderr.write(json.dumps(record, sort_keys=True) + "\n")
    sys.stderr.flush()


def get_logger(name: str) -> logging.Logger:
    """Return a stdlib logger (kept for backward compatibility)."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    return logging.getLogger(name)
