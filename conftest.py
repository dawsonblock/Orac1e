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
# Insert at position 0 so project-local modules always win over installed ones
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
