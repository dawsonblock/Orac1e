"""Approval endpoint authentication.

Requires a Bearer token matching the ORACLE_APPROVAL_TOKEN environment variable
for all state-changing approval/promotion endpoints.
"""

from __future__ import annotations

import os

from fastapi import Header, HTTPException


def require_approval_token(authorization: str | None = Header(default=None)) -> None:
    """FastAPI dependency that enforces Bearer token authentication.

    Raises:
        HTTPException: 401 if token is missing or invalid,
                       500 if ORACLE_APPROVAL_TOKEN is not configured.
    """
    expected = os.environ.get("ORACLE_APPROVAL_TOKEN")
    if not expected:
        raise HTTPException(
            status_code=500,
            detail="approval token not configured (set ORACLE_APPROVAL_TOKEN)",
        )
    if authorization != f"Bearer {expected}":
        raise HTTPException(status_code=401, detail="unauthorized")
