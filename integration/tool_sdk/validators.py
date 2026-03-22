from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import jsonschema
import requests

from .base_models import ToolManifestModel

# Configure logging
logger = logging.getLogger(__name__)

# Valid capability tags from capability_tags.md
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


def load_manifest_schema() -> dict[str, Any]:
    """Load the JSON schema for tool manifests."""
    schema_path = Path(__file__).parent / "manifest.schema.json"
    with open(schema_path, "r", encoding="utf-8") as f:
        return json.load(f)


# Cache the schema for repeated validations
_MANIFEST_SCHEMA: dict[str, Any] | None = None


def _get_manifest_schema() -> dict[str, Any]:
    """Get cached manifest schema."""
    global _MANIFEST_SCHEMA
    if _MANIFEST_SCHEMA is None:
        _MANIFEST_SCHEMA = load_manifest_schema()
    return _MANIFEST_SCHEMA


def validate_manifest_schema(payload: dict[str, Any]) -> list[str]:
    """
    Validate tool manifest against JSON schema.
    
    Returns a list of validation error messages. Empty list means valid.
    """
    errors: list[str] = []
    
    try:
        schema = _get_manifest_schema()
        validator = jsonschema.Draft202012Validator(schema)
        
        for error in validator.iter_errors(payload):
            # Build a user-friendly error message
            path = ".".join(str(p) for p in error.path) if error.path else "root"
            errors.append(f"{path}: {error.message}")
            
    except jsonschema.SchemaError as e:
        errors.append(f"Schema error: {e.message}")
    except Exception as e:
        errors.append(f"Unexpected validation error: {str(e)}")
    
    return errors


def validate_capability_tags(capabilities: list[str]) -> list[str]:
    """
    Validate that all capability tags are recognized.
    
    Returns a list of invalid capability tags. Empty list means all valid.
    """
    invalid_tags: list[str] = []
    
    for cap in capabilities:
        if cap not in VALID_CAPABILITY_TAGS:
            invalid_tags.append(cap)
    
    return invalid_tags


def check_tool_health(
    base_url: str,
    health_path: str,
    timeout_ms: int = 2000
) -> tuple[bool, str]:
    """
    Check if a tool service is healthy by calling its health endpoint.
    
    Returns a tuple of (is_healthy, message).
    """
    try:
        url = f"{base_url.rstrip('/')}{health_path}"
        response = requests.get(
            url,
            timeout=timeout_ms / 1000.0,
            headers={"Accept": "application/json"}
        )
        
        if response.status_code == 200:
            return True, f"Health check OK (status: {response.status_code})"
        else:
            return False, f"Health check failed (status: {response.status_code})"
            
    except requests.Timeout:
        return False, "Health check timed out"
    except requests.ConnectionError as e:
        return False, f"Health check connection failed: {str(e)}"
    except Exception as e:
        return False, f"Health check error: {str(e)}"


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
    
    @property
    def all_errors(self) -> list[str]:
        """Get all errors combined."""
        errors = []
        errors.extend(self.schema_errors)
        errors.extend(self.capability_errors)
        if self.health_message and self.health_status is not True:
            errors.append(self.health_message)
        return errors
    
    def __repr__(self) -> str:
        return (
            f"ManifestVerificationResult("
            f"is_valid={self.is_valid}, "
            f"schema_errors={len(self.schema_errors)}, "
            f"capability_errors={len(self.capability_errors)}, "
            f"health_status={self.health_status})"
        )


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
    
    Args:
        payload: The tool manifest dictionary to verify
        check_health: Whether to perform health check (default: True)
        health_timeout_ms: Health check timeout in milliseconds (default: from manifest or 2000ms)
    
    Returns:
        ManifestVerificationResult with verification status and details
    """
    # Step 1: Schema validation
    schema_errors = validate_manifest_schema(payload)
    if schema_errors:
        return ManifestVerificationResult(
            is_valid=False,
            schema_errors=schema_errors,
        )
    
    # Step 2: Pydantic model validation (existing behavior)
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
            schema_errors=[],
            capability_errors=capability_errors,
            model=model,
        )
    
    # Step 4: Optional health check
    health_status: bool | None = None
    health_message: str | None = None
    
    if check_health:
        timeout = health_timeout_ms or model.timeouts.health_ms
        health_status, health_message = check_tool_health(
            base_url=model.base_url,
            health_path=model.health_path,
            timeout_ms=timeout,
        )
        
        # Health check failure doesn't invalidate the manifest itself,
        # but indicates the tool service is not currently available
        logger.warning(
            f"Tool '{model.id}' health check: {health_message}"
        )
    
    return ManifestVerificationResult(
        is_valid=True,
        schema_errors=[],
        capability_errors=[],
        health_status=health_status,
        health_message=health_message,
        model=model,
    )


# Keep the original validate_manifest for backward compatibility
def validate_manifest(payload: dict) -> ToolManifestModel:
    """
    Validate tool manifest and return model.
    
    Note: This is the original function kept for backward compatibility.
    For comprehensive runtime verification, use verify_manifest() instead.
    """
    return ToolManifestModel.model_validate(payload)
