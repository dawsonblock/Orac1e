from __future__ import annotations

import json
import logging
from pathlib import Path

from .base_models import ToolManifestModel
from .validators import verify_manifest, ManifestVerificationResult

logger = logging.getLogger(__name__)


class ToolRegistry:
    def __init__(self, tools_root: str | Path):
        self.tools_root = Path(tools_root)
        self._tools: dict[str, ToolManifestModel] = {}

    def load(self, check_health: bool = False) -> None:
        """
        Load all tool manifests from the tools root directory.
        
        Args:
            check_health: Whether to perform health checks on load (default: False)
        """
        self._tools.clear()

        if not self.tools_root.exists():
            raise FileNotFoundError(f"tools root does not exist: {self.tools_root}")

        for tool_json in sorted(self.tools_root.glob("*/tool.json")):
            with tool_json.open("r", encoding="utf-8") as handle:
                data = json.load(handle)

            # Use comprehensive verification
            result = verify_manifest(data, check_health=check_health)
            
            if not result.is_valid or result.model is None:
                logger.error(
                    f"Tool manifest validation failed for {tool_json.name}: "
                    f"{result.all_errors}"
                )
                raise ValueError(
                    f"Invalid tool manifest {tool_json.name}: {result.all_errors}"
                )
            
            manifest = result.model

            if manifest.id in self._tools:
                raise ValueError(f"duplicate tool id: {manifest.id}")

            self._tools[manifest.id] = manifest
            logger.info(f"Loaded tool: {manifest.id} (health: {result.health_status})")

    def all(self) -> list[ToolManifestModel]:
        return list(self._tools.values())

    def get(self, tool_id: str) -> ToolManifestModel | None:
        return self._tools.get(tool_id)

    def by_kind(self, kind: str) -> list[ToolManifestModel]:
        return [tool for tool in self._tools.values() if tool.kind == kind]

    def by_capability(self, capability: str) -> list[ToolManifestModel]:
        return [tool for tool in self._tools.values() if capability in tool.capabilities]
    
    def verify_tool(self, tool_id: str, check_health: bool = True) -> ManifestVerificationResult:
        """
        Verify a specific tool manifest.
        
        Args:
            tool_id: The tool ID to verify
            check_health: Whether to perform health check
            
        Returns:
            ManifestVerificationResult with verification status
        """
        tool = self._tools.get(tool_id)
        if not tool:
            return ManifestVerificationResult(
                is_valid=False,
                schema_errors=[f"Tool not found: {tool_id}"],
            )
        
        # Convert model back to dict for re-verification
        payload = tool.model_dump()
        return verify_manifest(payload, check_health=check_health)
    
    def verify_all(self, check_health: bool = True) -> dict[str, ManifestVerificationResult]:
        """
        Verify all loaded tool manifests.
        
        Args:
            check_health: Whether to perform health checks
            
        Returns:
            Dictionary mapping tool_id to verification result
        """
        results = {}
        for tool_id in self._tools:
            results[tool_id] = self.verify_tool(tool_id, check_health=check_health)
        return results
