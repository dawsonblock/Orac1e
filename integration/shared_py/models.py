from __future__ import annotations

from typing import Any, Literal
from pydantic import BaseModel, Field


class ContextSnippet(BaseModel):
    path: str
    snippet: str
    start_line: int | None = None
    end_line: int | None = None
    score: float | None = None


class ProposeContext(BaseModel):
    files: list[str] = Field(default_factory=list)
    snippets: list[ContextSnippet] = Field(default_factory=list)
    docs: list[dict[str, Any]] = Field(default_factory=list)


class Constraints(BaseModel):
    allowed_paths: list[str] = Field(default_factory=list)
    max_files: int = 6
    max_changed_lines: int = 300
    allow_shell: bool = False


class ProposeRequest(BaseModel):
    run_id: str
    repo_name: str
    repo_path: str
    task: str
    mode: Literal['interactive', 'autonomous']
    context: ProposeContext
    constraints: Constraints


class ProposeResponse(BaseModel):
    status: Literal['ok', 'blocked', 'error']
    worker: str
    summary: str
    diff: str
    touched_files: list[str] = Field(default_factory=list)
    commands_requested: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    artifacts: list[dict[str, Any]] = Field(default_factory=list)


class RetrievalRequest(BaseModel):
    repo_name: str
    repo_path: str
    query: str
    top_k: int = 10
    paths: list[str] | None = None
    languages: list[str] | None = None
    refresh_index: bool = True


class RetrievalResult(BaseModel):
    path: str
    score: float
    snippet: str
    start_line: int
    end_line: int
    language: str


class RetrievalResponse(BaseModel):
    status: Literal['ok', 'error']
    results: list[RetrievalResult] = Field(default_factory=list)
    message: str | None = None


class HealthResponse(BaseModel):
    name: str
    ok: bool = True
    details: dict[str, Any] = Field(default_factory=dict)
