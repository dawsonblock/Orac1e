from __future__ import annotations

import os
from fastapi import FastAPI, HTTPException

from integration.shared_py.models import HealthResponse, ProposeRequest, ProposeResponse
from integration.tool_sdk.base_models import ToolInvokeEnvelope, ToolResponseEnvelope
from integration.worker_aider.runner import run_aider

app = FastAPI(title="worker-aider", version="0.2.0")

SUPPORTED_CAPABILITIES = {"worker.code.patch", "worker.code.interactive"}


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        name="worker-aider",
        details={
            "aider_bin": os.environ.get("AIDER_BIN", "python -m aider.main"),
            "aider_model": os.environ.get("AIDER_MODEL", ""),
            "capabilities": sorted(SUPPORTED_CAPABILITIES),
        },
    )


@app.post("/propose", response_model=ProposeResponse)
def propose(req: ProposeRequest) -> ProposeResponse:
    try:
        result = run_aider(req)
        return ProposeResponse(status="ok", worker="aider", **result)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/invoke", response_model=ToolResponseEnvelope)
def invoke(envelope: ToolInvokeEnvelope) -> ToolResponseEnvelope:
    if envelope.capability not in SUPPORTED_CAPABILITIES:
        return ToolResponseEnvelope(
            status="error",
            tool_id="aider",
            capability=envelope.capability,
            error="unsupported capability",
        )

    try:
        req = ProposeRequest.model_validate(envelope.payload)
        resp = ProposeResponse(status="ok", worker="aider", **run_aider(req))
        status = "ok" if resp.diff.strip() else "no_result"
        summary = resp.summary or ("No patch proposed" if status == "no_result" else "")
        metrics = {
            "touched_file_count": len(resp.touched_files),
            "warning_count": len(resp.warnings),
            "command_request_count": len(resp.commands_requested),
        }
        return ToolResponseEnvelope(
            status=status,
            tool_id="aider",
            capability=envelope.capability,
            summary=summary,
            payload=resp.model_dump(),
            warnings=resp.warnings,
            artifacts=[f"inline:{idx}" for idx, _ in enumerate(resp.artifacts)],
            metrics=metrics,
            error=None,
        )
    except Exception as exc:
        return ToolResponseEnvelope(
            status="error",
            tool_id="aider",
            capability=envelope.capability,
            summary="",
            payload={},
            warnings=[],
            artifacts=[],
            metrics={},
            error=str(exc),
        )
