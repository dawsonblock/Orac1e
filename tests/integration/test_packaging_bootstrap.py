from __future__ import annotations

from pathlib import Path
import tomllib


ROOT = Path(__file__).resolve().parents[2]


def test_root_pyproject_declares_bootstrap_dependencies() -> None:
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))

    assert pyproject["project"]["name"] == "oracle-system"
    assert pyproject["build-system"]["build-backend"] == "setuptools.build_meta"
    assert "setuptools" in pyproject["build-system"]["requires"]
    assert pyproject["project"]["dependencies"] == [
        "fastapi",
        "uvicorn",
        "pydantic",
        "pytest",
        "redis",
        "rq",
        "gitpython",
    ]


def test_requirements_use_local_editable_installs() -> None:
    requirements = (ROOT / "requirements.txt").read_text(encoding="utf-8")

    assert "git+https://github.com/dawsonblock/Orac1e.git" not in requirements
    assert "-e third_party/cocoindex-code" in requirements
    assert "-e third_party/code-agent-runtime" in requirements
    assert "-e ." in requirements


def test_bootstrap_installs_editables_without_pythonpath_hacks() -> None:
    bootstrap = (ROOT / "scripts" / "bootstrap_all.sh").read_text(encoding="utf-8")

    assert "python3 -m venv .venv" in bootstrap
    assert "source .venv/bin/activate" in bootstrap
    assert "pip install --upgrade pip" in bootstrap
    assert "pip install -r requirements.txt" in bootstrap
    assert "pip install -e ." in bootstrap
    assert "pip install -e third_party/aider" in bootstrap
    assert "pip install -e third_party/code-agent-runtime" in bootstrap
    assert "pip install -e third_party/cocoindex-code" in bootstrap
    assert "python - <<'PY'" in bootstrap
    assert "Import checks passed" in bootstrap
    assert "PYTHONPATH" not in bootstrap
    assert "requirements_bootstrap.txt" not in bootstrap
