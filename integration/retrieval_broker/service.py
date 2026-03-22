from __future__ import annotations

import os
from fastapi import FastAPI, HTTPException

from integration.shared_py.models import HealthResponse, RetrievalRequest, RetrievalResponse
from integration.retrieval_broker.coco_client import search_code
from integration.retrieval_broker.search_merge import sort_results
from integration.tool_sdk.base_models import ToolInvokeEnvelope, ToolResponseEnvelope

app = FastAPI(title="retrieval-broker", version="0.2.0")

SUPPORTED_CAPABILITIES = {"retrieval.code.search"}


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        name="retrieval-broker",
        details={
            "cocoindex_repo_path": os.environ.get("COCOINDEX_REPO_PATH", ""),
            "capabilities": sorted(SUPPORTED_CAPABILITIES),
        },
    )


@app.post("/search/code", response_model=RetrievalResponse)
async def search_code_endpoint(req: RetrievalRequest) -> RetrievalResponse:
    try:
        items = await search_code(req)
        return RetrievalResponse(status="ok", results=sort_results(items))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/invoke", response_model=ToolResponseEnvelope)
async def invoke(envelope: ToolInvokeEnvelope) -> ToolResponseEnvelope:
    if envelope.capability not in SUPPORTED_CAPABILITIES:
        return ToolResponseEnvelope(
            status="error",
            tool_id="cocoindex",
            capability=envelope.capability,
            error="unsupported capability",
        )

    try:
        req = RetrievalRequest.model_validate(envelope.payload)
        items = await search_code(req)
        resp = RetrievalResponse(status="ok", results=sort_results(items))
        status = "ok" if resp.results else "no_result"
        summary = f"Retrieved {len(resp.results)} code matches" if resp.results else "No code matches found"
        return ToolResponseEnvelope(
            status=status,
            tool_id="cocoindex",
            capability=envelope.capability,
            summary=summary,
            payload=resp.model_dump(),
            warnings=[],
            artifacts=[],
            metrics={"result_count": len(resp.results)},
            error=None,
        )
    except Exception as exc:
        return ToolResponseEnvelope(
            status="error",
            tool_id="cocoindex",
            capability=envelope.capability,
            summary="",
            payload={},
            warnings=[],
            artifacts=[],
            metrics={},
            error=str(exc),
        )
