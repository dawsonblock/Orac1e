# Manifest-Driven Tool Discovery Pattern

## Intent

Oracle Build v5 implements a **self-describing tool ecosystem** where each tool declares its capabilities, constraints, and endpoints via a `tool.json` manifest. Oracle discovers tools at startup through the `ToolRegistry`, selects tools by capability rather than name, and invokes them through a generic envelope interface.

## Motivation

Traditional tool integration requires hardcoded tool names and paths in the calling code. The manifest-driven approach provides:

| Benefit | Description |
|---------|-------------|
| **Decoupling** | Oracle doesn't need to know tool implementations, only interfaces |
| **Discovery** | New tools are auto-discovered by dropping them into the tools directory |
| **Capability-based routing** | Select tools by what they can do, not who they are |
| **Health monitoring** | Tools self-report health status |
| **Type safety** | Pydantic models validate manifests at load time |

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Oracle OS (Authority)                     │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                  ToolRegistry                           │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │ load() → discovers all tool.json files            │  │  │
│  │  │ by_capability(cap) → tools matching capability    │  │  │
│  │  │ by_kind(kind) → tools of specific kind            │  │  │
│  │  │ verify_all() → health check all tools             │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│                              │                                │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                   ToolRouter                            │  │
│  │  Selects tool by capability, not name                    │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                    Tool Services                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │
│  │    Aider   │  │  Hardened   │  │     Cocoindex       │   │
│  │  tool.json │  │  tool.json  │  │      tool.json       │   │
│  └─────────────┘  └─────────────┘  └─────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

## Tool Manifest Schema

Each tool must provide a `tool.json` conforming to the manifest schema:

### Example: Hardened Worker Manifest

```json
{
  "id": "hardened",
  "name": "Code Agent Runtime - Hardened",
  "version": "0.2.0",
  "api_version": "1.0",
  "kind": "worker",
  "capabilities": [
    "worker.code.patch",
    "worker.code.issue_fix"
  ],
  "base_url": "http://localhost:8092",
  "health_path": "/health",
  "invoke_path": "/invoke",
  "risk_level": "medium",
  "repo_languages": ["python", "javascript", "typescript", "rust", "go"],
  "timeouts": {
    "health_ms": 2000,
    "invoke_ms": 300000
  },
  "concurrency": {
    "max_global": 10,
    "max_per_repo": 2
  },
  "features": {
    "supports_diff": true,
    "supports_streaming": false,
    "supports_cancellation": true
  }
}
```

## Core Models ([`integration/tool_sdk/base_models.py`](../../../../integration/tool_sdk/base_models.py:35))

```python
from pydantic import BaseModel, ConfigDict, Field, field_validator
from typing import Any, Literal

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
```

## Capability Tags Vocabulary

Tools declare capabilities from a controlled vocabulary:

```python
# From integration/tool_sdk/validators.py
VALID_CAPABILITY_TAGS: frozenset[str] = frozenset({
    # Workers
    "worker.code.patch",
    "worker.code.interactive",
    "worker.code.issue_fix",
    # Retrieval
    "retrieval.code.search",
    "retrieval.code.symbols",
    "retrieval.code.tests",
    # Validators
    "validator.code.lint",
    "validator.code.tests",
    "validator.code.build",
    "validator.code.security",
    # Actions
    "action.git.pr_draft",
    "action.git.comment",
    "action.git.branch_info",
})
```

## ToolRegistry Implementation ([`integration/tool_sdk/registry.py`](../../../../integration/tool_sdk/registry.py:13))

```python
from pathlib import Path
from .base_models import ToolManifestModel
from .validators import verify_manifest, ManifestVerificationResult

class ToolRegistry:
    def __init__(self, tools_root: str | Path):
        self.tools_root = Path(tools_root)
        self._tools: dict[str, ToolManifestModel] = {}

    def load(self, check_health: bool = False) -> None:
        """Load all tool manifests from the tools root directory."""
        self._tools.clear()

        if not self.tools_root.exists():
            raise FileNotFoundError(f"tools root does not exist: {self.tools_root}")

        for tool_json in sorted(self.tools_root.glob("*/tool.json")):
            with tool_json.open("r", encoding="utf-8") as handle:
                data = json.load(handle)

            # Comprehensive verification
            result = verify_manifest(data, check_health=check_health)
            
            if not result.is_valid or result.model is None:
                raise ValueError(
                    f"Invalid tool manifest {tool_json.name}: {result.all_errors}"
                )
            
            manifest = result.model
            self._tools[manifest.id] = manifest
            logger.info(f"Loaded tool: {manifest.id} (health: {result.health_status})")

    def by_capability(self, capability: str) -> list[ToolManifestModel]:
        """Find all tools supporting a given capability."""
        return [tool for tool in self._tools.values() if capability in tool.capabilities]

    def by_kind(self, kind: str) -> list[ToolManifestModel]:
        """Find all tools of a specific kind."""
        return [tool for tool in self._tools.values() if tool.kind == kind]
```

## Invocation Envelope Pattern

### Request Envelope

```python
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
```

### Response Envelope

```python
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
```

## Validation Pipeline ([`integration/tool_sdk/validators.py`](../../../../integration/tool_sdk/validators.py:167))

```python
class ManifestVerificationResult:
    """Result of manifest verification."""
    
    def __init__(
        self,
        is_valid: bool,
        schema_errors: list[str] | None = None,
        capability_errors: list[str] | None = None,
        health_status: bool | None = None,
        health_message: str | None = None,
        model: ToolManifestModel | None = None,
    ):
        self.is_valid = is_valid
        self.schema_errors = schema_errors or []
        self.capability_errors = capability_errors or []
        self.health_status = health_status
        self.health_message = health_message
        self.model = model

def verify_manifest(
    payload: dict[str, Any],
    check_health: bool = True,
    health_timeout_ms: int | None = None,
) -> ManifestVerificationResult:
    """
    Perform comprehensive verification of a tool manifest.
    
    This includes:
    1. Schema validation (required fields, types, patterns)
    2. Capability tag validation against known vocabulary
    3. Optional health check of the tool service
    """
    # Step 1: Schema validation
    schema_errors = validate_manifest_schema(payload)
    if schema_errors:
        return ManifestVerificationResult(is_valid=False, schema_errors=schema_errors)
    
    # Step 2: Pydantic model validation
    try:
        model = ToolManifestModel.model_validate(payload)
    except Exception as e:
        return ManifestVerificationResult(
            is_valid=False,
            schema_errors=[f"Model validation error: {str(e)}"],
        )
    
    # Step 3: Capability tag validation
    capability_errors = validate_capability_tags(model.capabilities)
    if capability_errors:
        return ManifestVerificationResult(
            is_valid=False,
            capability_errors=capability_errors,
            model=model,
        )
    
    # Step 4: Optional health check
    if check_health:
        timeout = health_timeout_ms or model.timeouts.health_ms
        health_status, health_message = check_tool_health(
            base_url=model.base_url,
            health_path=model.health_path,
            timeout_ms=timeout,
        )
    
    return ManifestVerificationResult(
        is_valid=True,
        health_status=health_status,
        health_message=health_message,
        model=model,
    )
```

## Usage Pattern

```python
# Initialize registry
registry = ToolRegistry(tools_root="integration/tools/")
registry.load(check_health=True)

# Find tools by capability (not by name!)
workers = registry.by_capability("worker.code.patch")
print(f"Found {len(workers)} tools for worker.code.patch: {[t.id for t in workers]}")

# Find tools by kind
all_workers = registry.by_kind("worker")
all_retrievers = registry.by_kind("retrieval")

# Get specific tool
hardened = registry.get("hardened")
if hardened:
    print(f"Hardened version: {hardened.version}")
```

## Tool Discovery Flow

```
1. Oracle starts
       │
       ▼
2. ToolRegistry.load() scans integration/tools/*/tool.json
       │
       ▼
3. Each manifest is validated (schema + capabilities + health)
       │
       ├── Invalid manifest → raise ValueError, fail startup
       │
       └── Valid manifest → add to registry
       │
       ▼
4. Oracle queries registry by capability to find suitable tools
       │
       ▼
5. Oracle invokes tool via /invoke endpoint with envelope
       │
       ▼
6. Tool returns ToolResponseEnvelope
```

## Benefits Realized

| Problem | Solution |
|---------|----------|
| Adding new tool requires code changes | Drop new `tool.json`, restart Oracle |
| Hardcoded tool URLs | `base_url` in manifest |
| Unknown tool health | Health check on load |
| Capability routing | `by_capability()` query |
| Invalid tool configs | Schema + Pydantic validation |
| External tool failures | Health status in verification result |

## Related Patterns

- [Dual-Worker Architecture](dual-worker-architecture.md) - How workers use this discovery mechanism
- [Validation Pipeline](validation-pipeline.md) - How validators are also discovered