from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


def init_python_repo(path: Path) -> None:
    subprocess.run(["git", "init", "-b", "main"], cwd=path, check=True, capture_output=True, text=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=path, check=True, capture_output=True, text=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=path, check=True, capture_output=True, text=True)
    (path / "src").mkdir()
    (path / "tests").mkdir()
    (path / "domains" / "code").mkdir(parents=True)
    (path / "src" / "calc.py").write_text("def inc(x):\n    return x + 2\n", encoding="utf-8")
    (path / "tests" / "test_calc.py").write_text(
        "from src.calc import inc\n\n\ndef test_inc():\n    assert inc(1) == 2\n",
        encoding="utf-8",
    )
    contract_src = Path(__file__).resolve().parents[1] / "domains" / "code" / "contracts.yaml"
    shutil.copy2(contract_src, path / "domains" / "code" / "contracts.yaml")
    subprocess.run(["git", "add", "."], cwd=path, check=True, capture_output=True, text=True)
    subprocess.run(["git", "commit", "-m", "init"], cwd=path, check=True, capture_output=True, text=True)
