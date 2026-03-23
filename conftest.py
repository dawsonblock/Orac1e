"""Root conftest: ensure the project root and scripts/ are on sys.path.

This lets tests do:
    from scripts.coding_run_promotion import ...
    from integration.shared_py.models import ...

without needing explicit PYTHONPATH manipulation in every test file.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VENDORED_PATHS = [
    ROOT,
    ROOT / "third_party" / "code-agent-runtime",
    ROOT / "third_party" / "cocoindex-code" / "src",
]

for path in reversed(VENDORED_PATHS):
    if path.exists() and str(path) not in sys.path:
        sys.path.insert(0, str(path))
