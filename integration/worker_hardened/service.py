from __future__ import annotations

import os
from fastapi import FastAPI, HTTPException

from integration.shared_py.models import HealthResponse, ProposeRequest, ProposeResponse
from integration.tool_sdk.base_models import ToolInvokeEnvelope, ToolResponseEnvelope
from integration.worker_hardened.bridge import run_hardened

app = FastAPI(title="worker-hardened", version="0.2.0")

SUPPORTED_CAPABILITIES = {"worker.code.patch", "worker.code.issue_fix"}


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        name="worker-hardened",
        details={
            "code_agent_repo_path": os.environ.get("CODE_AGENT_REPO_PATH", ""),
            "capabilities": sorted(SUPPORTED_CAPABILITIES),
        },
    )


@app.post("/propose", response_model=ProposeResponse)
def propose(req: ProposeRequest) -> ProposeResponse:
    try:
        result = run_hardened(req)
        return ProposeResponse(status="ok", worker="code-agent-runtime-hardened", **result)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/invoke", response_model=ToolResponseEnvelope)
def invoke(envelope: ToolInvokeEnvelope) -> ToolResponseEnvelope:
    if envelope.capability not in SUPPORTED_CAPABILITIES:
        return ToolResponseEnvelope(
            status="error",
            tool_id="hardened",
            capability=envelope.capability,
            error="unsupported capability",
        )

    try:
        req = ProposeRequest.model_validate(envelope.payload)
        resp = ProposeResponse(status="ok", worker="code-agent-runtime-hardened", **run_hardened(req))
        status = "ok" if resp.diff.strip() else "no_result"
        summary = resp.summary or ("No patch proposed" if status == "no_result" else "")
        metrics = {
            "touched_file_count": len(resp.touched_files),
            "warning_count": len(resp.warnings),
            "command_request_count": len(resp.commands_requested),
        }
        return ToolResponseEnvelope(
            status=status,
            tool_id="hardened",
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
            tool_id="hardened",
            capability=envelope.capability,
            summary="",
            payload={},
            warnings=[],
            artifacts=[],
            metrics={},
            error=str(exc),
        )
