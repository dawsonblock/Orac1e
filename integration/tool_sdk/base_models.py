from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


ToolKind = Literal["worker", "retrieval", "validator", "action"]
RiskLevel = Literal["low", "medium", "high"]
EnvelopeStatus = Literal["ok", "error", "no_result"]


class ToolTimeoutsModel(BaseModel):
    model_config = ConfigDict(extra="forbid")

    health_ms: int = Field(ge=100)
    invoke_ms: int = Field(ge=1000)


class ToolConcurrencyModel(BaseModel):
    model_config = ConfigDict(extra="forbid")

    max_global: int = Field(ge=1)
    max_per_repo: int = Field(ge=1)


class ToolFeaturesModel(BaseModel):
    model_config = ConfigDict(extra="forbid")

    supports_diff: bool
    supports_streaming: bool
    supports_cancellation: bool


class ToolManifestModel(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    name: str
    version: str
    api_version: str
    kind: ToolKind
    capabilities: list[str]
    base_url: str
    health_path: str
    invoke_path: str
    risk_level: RiskLevel
    repo_languages: list[str] = Field(default_factory=list)
    timeouts: ToolTimeoutsModel
    concurrency: ToolConcurrencyModel
    features: ToolFeaturesModel

    @field_validator("id")
    @classmethod
    def validate_id(cls, value: str) -> str:
        if not value or value.strip() != value:
            raise ValueError("tool id must be non-empty and trimmed")
        return value

    @field_validator("capabilities")
    @classmethod
    def validate_capabilities(cls, value: list[str]) -> list[str]:
        if not value:
            raise ValueError("capabilities must not be empty")
        cleaned: list[str] = []
        seen: set[str] = set()
        for item in value:
            item = item.strip()
            if not item:
                raise ValueError("capability values must not be blank")
            if item not in seen:
                cleaned.append(item)
                seen.add(item)
        return cleaned


class ToolInvokeEnvelope(BaseModel):
    model_config = ConfigDict(extra="forbid")

    contract_version: str = "1.0"
    run_id: str
    tool_id: str
    capability: str
    payload: dict[str, Any] = Field(default_factory=dict)
    constraints: dict[str, Any] = Field(default_factory=dict)
    context: dict[str, Any] = Field(default_factory=dict)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @field_validator("run_id", "tool_id", "capability")
    @classmethod
    def non_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("field must not be blank")
        return value


class ToolResponseEnvelope(BaseModel):
    model_config = ConfigDict(extra="forbid")

    contract_version: str = "1.0"
    status: EnvelopeStatus
    tool_id: str
    capability: str
    summary: str = ""
    payload: dict[str, Any] = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)
    artifacts: list[str] = Field(default_factory=list)
    metrics: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None

    @field_validator("tool_id", "capability")
    @classmethod
    def response_non_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("field must not be blank")
        return value
