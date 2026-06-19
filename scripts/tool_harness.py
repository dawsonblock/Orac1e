#!/usr/bin/env python3
"""Tool harness — loads tool manifests and checks health of each tool.

Usage:
    python3 scripts/tool_harness.py
    python3 -m scripts.tool_harness
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from integration.tool_sdk.harness import run_harness  # noqa: E402


def main() -> int:
    result = run_harness("integration/tools")
    print(json.dumps(result, indent=2))

    # Fail if any tool is unhealthy
    if isinstance(result, dict):
        for tool_id, info in result.items():
            if isinstance(info, dict) and not info.get("healthy", True):
                print(f"UNHEALTHY: {tool_id}", file=sys.stderr)
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
