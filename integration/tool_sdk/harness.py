from __future__ import annotations

import requests

from .registry import ToolRegistry


def run_harness(tools_root: str) -> list[dict]:
    registry = ToolRegistry(tools_root)
    registry.load()

    results: list[dict] = []

    for tool in registry.all():
        url = f"{tool.base_url.rstrip('/')}{tool.health_path}"
        ok = False
        error = None

        try:
            response = requests.get(url, timeout=tool.timeouts.health_ms / 1000.0)
            ok = response.status_code == 200
            if not ok:
                error = f"health returned {response.status_code}"
        except Exception as exc:
            error = str(exc)

        results.append(
            {
                "tool_id": tool.id,
                "kind": tool.kind,
                "capabilities": tool.capabilities,
                "ok": ok,
                "error": error,
            }
        )

    return results


if __name__ == "__main__":
    import json
    import sys

    root = sys.argv[1] if len(sys.argv) > 1 else "integration/tools"
    print(json.dumps(run_harness(root), indent=2))
