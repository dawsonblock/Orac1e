"""Comprehensive tests for tool manifest loading, invocation, and validation.

This module tests:
1. Tool registry loading and filtering
2. Manifest validation and verification
3. Health check handling
4. Edge cases and error scenarios
"""
import json
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest
import requests

from integration.tool_sdk.registry import ToolRegistry
from integration.tool_sdk.validators import (
    verify_manifest,
    validate_manifest_schema,
    validate_capability_tags,
    check_tool_health,
    ManifestVerificationResult,
)
from integration.tool_sdk.base_models import ToolManifestModel


# =============================================================================
# TOOL REGISTRY TESTS
# =============================================================================

class TestToolRegistryLoading:
    """Tests for tool registry loading functionality."""

    def test_tool_registry_loads_from_integration_tools(self, tmp_path):
        """Test that tool manifest loads from integration tools directory."""
        # Create a mock tool.json file
        tool_dir = tmp_path / "mock_tool"
        tool_dir.mkdir()
        
        tool_json = tool_dir / "tool.json"
        tool_json.write_text('''{
            "id": "mock-tool",
            "name": "Mock Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["worker.code.patch"],
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "medium",
            "timeouts": {
                "health_ms": 2000,
                "invoke_ms": 30000
            },
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": true, "supports_streaming": false, "supports_cancellation": false}
        }''')
        
        # Create registry and load tools
        registry = ToolRegistry(tmp_path)
        registry.load()
        
        # Verify tool was loaded
        tool = registry.get("mock-tool")
        assert tool is not None, "Tool should be loaded"
        assert tool.id == "mock-tool", "Tool ID should match"
        assert tool.name == "Mock Tool", "Tool name should match"
        assert tool.kind == "worker", "Tool kind should match"
        assert "worker.code.patch" in tool.capabilities, \
            "Capability should be present"

    def test_tool_registry_missing_tools_root_raises(self, tmp_path):
        """Test that missing tools root raises FileNotFoundError."""
        nonexistent = tmp_path / "nonexistent"
        
        registry = ToolRegistry(nonexistent)
        
        with pytest.raises(FileNotFoundError, match="tools root does not exist"):
            registry.load()

    def test_tool_registry_duplicate_id_raises(self, tmp_path):
        """Test that duplicate tool IDs raise ValueError."""
        tool_dir = tmp_path / "tool_a"
        tool_dir.mkdir()
        (tool_dir / "tool.json").write_text('''{
            "id": "duplicate-tool",
            "name": "Tool A",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["worker.code.patch"],
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {"health_ms": 2000, "invoke_ms": 30000},
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": true, "supports_streaming": false, "supports_cancellation": false}
        }''')
        
        # Create second tool with same ID
        tool_dir2 = tmp_path / "tool_b"
        tool_dir2.mkdir()
        (tool_dir2 / "tool.json").write_text('''{
            "id": "duplicate-tool",
            "name": "Tool B",
            "kind": "retrieval",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["retrieval.code.search"],
            "base_url": "http://localhost:8001",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {"health_ms": 2000, "invoke_ms": 30000},
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": true, "supports_streaming": false, "supports_cancellation": false}
        }''')
        
        registry = ToolRegistry(tmp_path)
        
        with pytest.raises(ValueError, match="duplicate tool id"):
            registry.load()


class TestToolRegistryFiltering:
    """Tests for tool filtering functionality."""

    def test_tool_registry_by_kind(self, tmp_path):
        """Test that tools can be filtered by kind."""
        # Create mock tool directories
        for tool_name in ["tool-a", "tool-b"]:
            tool_dir = tmp_path / tool_name
            tool_dir.mkdir()
            tool_json = tool_dir / "tool.json"
            tool_json.write_text(f'''{{
                "id": "{tool_name}",
                "name": "Tool {tool_name}",
                "kind": "retrieval",
                "api_version": "1.0",
                "version": "1.0.0",
                "capabilities": ["retrieval.code.search"],
                "base_url": "http://localhost:8000",
                "health_path": "/health",
                "invoke_path": "/invoke",
                "risk_level": "low",
                "timeouts": {{"health_ms": 2000, "invoke_ms": 30000}},
                "concurrency": {{"max_global": 1, "max_per_repo": 1}},
                "features": {{"supports_diff": true, "supports_streaming": false, "supports_cancellation": false}}
            }}''')
        
        registry = ToolRegistry(tmp_path)
        registry.load()
        
        # Verify tools are loaded and can be filtered by kind
        retrieval_tools = registry.by_kind("retrieval")
        assert len(retrieval_tools) == 2, \
            "Should find 2 retrieval tools"
        assert all(tool.kind == "retrieval" for tool in retrieval_tools), \
            "All filtered tools should be retrieval kind"

    def test_tool_registry_by_capability(self, tmp_path):
        """Test that tools can be filtered by capability."""
        tool_dir = tmp_path / "capability_tool"
        tool_dir.mkdir()
        tool_json = tool_dir / "tool.json"
        tool_json.write_text('''{
            "id": "capability-tool",
            "name": "Capability Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["worker.code.patch", "worker.code.interactive"],
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "medium",
            "timeouts": {"health_ms": 2000, "invoke_ms": 30000},
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": true, "supports_streaming": false, "supports_cancellation": false}
        }''')
        
        registry = ToolRegistry(tmp_path)
        registry.load()
        
        # Verify tools can be filtered by capability
        patch_tools = registry.by_capability("worker.code.patch")
        assert len(patch_tools) == 1, \
            "Should find 1 tool with worker.code.patch"
        assert "worker.code.patch" in patch_tools[0].capabilities, \
            "Tool should have worker.code.patch capability"
        
        interactive_tools = registry.by_capability("worker.code.interactive")
        assert len(interactive_tools) == 1, \
            "Should find 1 tool with worker.code.interactive"

    def test_tool_registry_all_returns_list(self, tmp_path):
        """Test that all() returns a list of all tools."""
        tool_dir = tmp_path / "test_tool"
        tool_dir.mkdir()
        (tool_dir / "tool.json").write_text('''{
            "id": "test-tool",
            "name": "Test Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["worker.code.patch"],
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {"health_ms": 2000, "invoke_ms": 30000},
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": true, "supports_streaming": false, "supports_cancellation": false}
        }''')
        
        registry = ToolRegistry(tmp_path)
        registry.load()
        
        all_tools = registry.all()
        assert isinstance(all_tools, list), \
            "all() should return a list"
        assert len(all_tools) == 1, \
            "Should return exactly 1 tool"


# =============================================================================
# MANIFEST VALIDATION TESTS
# =============================================================================

class TestManifestSchemaValidation:
    """Tests for manifest schema validation."""

    def test_validate_manifest_schema_valid(self):
        """Test validation of a valid manifest."""
        valid_manifest = {
            "id": "test-tool",
            "name": "Test Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["worker.code.patch"],
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {
                "health_ms": 2000,
                "invoke_ms": 30000
            },
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": True, "supports_streaming": False, "supports_cancellation": False}
        }
        
        errors = validate_manifest_schema(valid_manifest)
        
        assert errors == [], \
            f"Valid manifest should have no errors, got: {errors}"

    def test_validate_manifest_schema_missing_required(self):
        """Test validation catches missing required fields."""
        incomplete_manifest = {
            "id": "test-tool",
            "name": "Test Tool",
            # Missing other required fields
        }
        
        errors = validate_manifest_schema(incomplete_manifest)
        
        assert len(errors) > 0, \
            "Incomplete manifest should have validation errors"

    def test_validate_manifest_schema_invalid_type(self):
        """Test validation catches invalid field types."""
        invalid_manifest = {
            "id": "test-tool",
            "name": "Test Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": 123,  # Should be list, not int
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {"health_ms": 2000, "invoke_ms": 30000},
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": True, "supports_streaming": False, "supports_cancellation": False}
        }
        
        errors = validate_manifest_schema(invalid_manifest)
        
        assert len(errors) > 0, \
            "Invalid type should produce validation errors"


class TestCapabilityValidation:
    """Tests for capability tag validation."""

    def test_validate_capability_tags_valid(self):
        """Test validation of valid capability tags."""
        valid_caps = ["worker.code.patch", "retrieval.code.search", "validator.code.lint"]
        
        invalid = validate_capability_tags(valid_caps)
        
        assert invalid == [], \
            f"Valid capabilities should have no errors, got: {invalid}"

    def test_validate_capability_tags_invalid(self):
        """Test validation catches invalid capability tags."""
        invalid_caps = ["invalid.capability", "fake.worker"]
        
        invalid = validate_capability_tags(invalid_caps)
        
        assert len(invalid) == 2, \
            "Should find 2 invalid capabilities"
        assert "invalid.capability" in invalid, \
            "invalid.capability should be flagged"
        assert "fake.worker" in invalid, \
            "fake.worker should be flagged"

    def test_validate_capability_tags_mixed(self):
        """Test validation with mixed valid/invalid capabilities."""
        mixed_caps = ["worker.code.patch", "invalid.capability"]
        
        invalid = validate_capability_tags(mixed_caps)
        
        assert len(invalid) == 1, \
            "Should find 1 invalid capability"
        assert "invalid.capability" in invalid, \
            "Only invalid.capability should be flagged"


# =============================================================================
# HEALTH CHECK TESTS
# =============================================================================

class TestHealthChecks:
    """Tests for tool health check functionality."""

    @patch('requests.get')
    def test_check_tool_health_success(self, mock_get):
        """Test successful health check."""
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_get.return_value = mock_response
        
        is_healthy, message = check_tool_health(
            base_url="http://localhost:8000",
            health_path="/health",
            timeout_ms=2000
        )
        
        assert is_healthy is True, \
            "Health check should succeed"
        assert "200" in message, \
            "Message should indicate status code"

    @patch('requests.get')
    def test_check_tool_health_failure(self, mock_get):
        """Test failed health check."""
        mock_response = MagicMock()
        mock_response.status_code = 503
        mock_get.return_value = mock_response
        
        is_healthy, message = check_tool_health(
            base_url="http://localhost:8000",
            health_path="/health",
            timeout_ms=2000
        )
        
        assert is_healthy is False, \
            "Health check should fail"
        assert "503" in message, \
            "Message should indicate failure status"

    @patch('requests.get')
    def test_check_tool_health_timeout(self, mock_get):
        """Test health check timeout handling."""
        mock_get.side_effect = requests.Timeout()
        
        is_healthy, message = check_tool_health(
            base_url="http://localhost:8000",
            health_path="/health",
            timeout_ms=2000
        )
        
        assert is_healthy is False, \
            "Timeout should result in unhealthy"
        assert "timed out" in message.lower(), \
            "Message should indicate timeout"

    @patch('requests.get')
    def test_check_tool_health_connection_error(self, mock_get):
        """Test health check connection error handling."""
        mock_get.side_effect = requests.ConnectionError("Connection refused")
        
        is_healthy, message = check_tool_health(
            base_url="http://localhost:8000",
            health_path="/health",
            timeout_ms=2000
        )
        
        assert is_healthy is False, \
            "Connection error should result in unhealthy"


# =============================================================================
# COMPREHENSIVE VERIFICATION TESTS
# =============================================================================

class TestManifestVerification:
    """Tests for comprehensive manifest verification."""

    def test_verify_manifest_valid(self):
        """Test verification of a valid manifest."""
        valid_manifest = {
            "id": "test-tool",
            "name": "Test Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["worker.code.patch"],
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {
                "health_ms": 2000,
                "invoke_ms": 30000
            },
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": True, "supports_streaming": False, "supports_cancellation": False}
        }
        
        # Mock health check to avoid network calls
        with patch('requests.get') as mock_get:
            mock_response = MagicMock()
            mock_response.status_code = 200
            mock_get.return_value = mock_response
            
            result = verify_manifest(valid_manifest, check_health=True)
        
        assert result.is_valid is True, \
            "Valid manifest should verify successfully"
        assert result.model is not None, \
            "Result should contain validated model"
        assert len(result.all_errors) == 0, \
            "Should have no errors"

    def test_verify_manifest_invalid_schema(self):
        """Test verification fails for invalid schema."""
        invalid_manifest = {
            "id": "test-tool",
            # Missing required fields
        }
        
        result = verify_manifest(invalid_manifest, check_health=False)
        
        assert result.is_valid is False, \
            "Invalid schema should fail verification"
        assert len(result.schema_errors) > 0, \
            "Should have schema errors"

    def test_verify_manifest_invalid_capabilities(self):
        """Test verification fails for invalid capability tags."""
        invalid_caps_manifest = {
            "id": "test-tool",
            "name": "Test Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["invalid.capability.tag"],
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {"health_ms": 2000, "invoke_ms": 30000},
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": True, "supports_streaming": False, "supports_cancellation": False}
        }
        
        result = verify_manifest(invalid_caps_manifest, check_health=False)
        
        assert result.is_valid is False, \
            "Invalid capabilities should fail verification"
        assert len(result.capability_errors) > 0, \
            "Should have capability errors"


class TestVerificationResult:
    """Tests for ManifestVerificationResult class."""

    def test_all_errors_combines_errors(self):
        """Test that all_errors combines all error types."""
        result = ManifestVerificationResult(
            is_valid=False,
            schema_errors=["schema error 1"],
            capability_errors=["capability error 1"],
            health_message="health error",
        )
        
        all_errs = result.all_errors
        
        assert len(all_errs) == 3, \
            "Should combine all error types"
        assert "schema error 1" in all_errs, \
            "Should include schema errors"
        assert "capability error 1" in all_errs, \
            "Should include capability errors"
        assert "health error" in all_errs, \
            "Should include health message"

    def test_repr_includes_status(self):
        """Test string representation includes key status."""
        result = ManifestVerificationResult(
            is_valid=True,
            health_status=True,
        )
        
        repr_str = repr(result)
        
        assert "is_valid=True" in repr_str, \
            "Should include is_valid status"


# =============================================================================
# EDGE CASES AND ERROR SCENARIOS
# =============================================================================

class TestToolRegistryEdgeCases:
    """Tests for edge cases in tool registry."""

    def test_registry_get_nonexistent_tool(self, tmp_path):
        """Test getting a nonexistent tool returns None."""
        tool_dir = tmp_path / "test_tool"
        tool_dir.mkdir()
        (tool_dir / "tool.json").write_text('''{
            "id": "test-tool",
            "name": "Test Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["worker.code.patch"],
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {"health_ms": 2000, "invoke_ms": 30000},
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": true, "supports_streaming": false, "supports_cancellation": false}
        }''')
        
        registry = ToolRegistry(tmp_path)
        registry.load()
        
        result = registry.get("nonexistent-tool")
        
        assert result is None, \
            "Nonexistent tool should return None"

    def test_registry_by_kind_no_matches(self, tmp_path):
        """Test filtering by kind with no matches."""
        tool_dir = tmp_path / "test_tool"
        tool_dir.mkdir()
        (tool_dir / "tool.json").write_text('''{
            "id": "test-tool",
            "name": "Test Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["worker.code.patch"],
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {"health_ms": 2000, "invoke_ms": 30000},
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": true, "supports_streaming": false, "supports_cancellation": false}
        }''')
        
        registry = ToolRegistry(tmp_path)
        registry.load()
        
        results = registry.by_kind("retrieval")
        
        assert results == [], \
            "Should return empty list when no matches"

    def test_registry_by_capability_no_matches(self, tmp_path):
        """Test filtering by capability with no matches."""
        tool_dir = tmp_path / "test_tool"
        tool_dir.mkdir()
        (tool_dir / "tool.json").write_text('''{
            "id": "test-tool",
            "name": "Test Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["worker.code.patch"],
            "base_url": "http://localhost:8000",
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {"health_ms": 2000, "invoke_ms": 30000},
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": true, "supports_streaming": false, "supports_cancellation": false}
        }''')
        
        registry = ToolRegistry(tmp_path)
        registry.load()
        
        results = registry.by_capability("nonexistent.capability")
        
        assert results == [], \
            "Should return empty list when no matches"


class TestManifestEdgeCases:
    """Tests for edge cases in manifest handling."""

    def test_verify_empty_manifest(self):
        """Test verification of empty manifest."""
        result = verify_manifest({}, check_health=False)
        
        assert result.is_valid is False, \
            "Empty manifest should fail verification"

    def test_verify_manifest_url_normalization(self):
        """Test that base URLs are handled correctly."""
        manifest = {
            "id": "test-tool",
            "name": "Test Tool",
            "kind": "worker",
            "api_version": "1.0",
            "version": "1.0.0",
            "capabilities": ["worker.code.patch"],
            "base_url": "http://localhost:8000/",  # Trailing slash
            "health_path": "/health",
            "invoke_path": "/invoke",
            "risk_level": "low",
            "timeouts": {"health_ms": 2000, "invoke_ms": 30000},
            "concurrency": {"max_global": 1, "max_per_repo": 1},
            "features": {"supports_diff": True, "supports_streaming": False, "supports_cancellation": False}
        }
        
        with patch('requests.get') as mock_get:
            mock_response = MagicMock()
            mock_response.status_code = 200
            mock_get.return_value = mock_response
            
            result = verify_manifest(manifest, check_health=True)
        
        assert result.is_valid is True, \
            "URL with trailing slash should still validate"
