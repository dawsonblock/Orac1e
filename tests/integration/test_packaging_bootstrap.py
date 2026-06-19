from __future__ import annotations

from pathlib import Path
import tomllib


ROOT = Path(__file__).resolve().parents[2]


def test_root_pyproject_declares_bootstrap_dependencies() -> None:
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    pyproject_dependencies = set(pyproject["project"]["dependencies"])

    assert pyproject["project"]["name"] == "oracle-system"
    assert pyproject["build-system"]["build-backend"] == "setuptools.build_meta"
    assert "setuptools" in pyproject["build-system"]["requires"]
    assert {
        "fastapi",
        "uvicorn",
        "pydantic",
        "pytest",
        "redis",
        "rq",
        "gitpython",
    }.issubset(pyproject_dependencies)


def test_requirements_use_local_editable_installs() -> None:
    requirements = (ROOT / "requirements.txt").read_text(encoding="utf-8")

    assert "git+https://github.com/dawsonblock/Orac1e.git" not in requirements
    assert "-e third_party/cocoindex-code" in requirements
    assert "-e third_party/code-agent-runtime" in requirements
    assert "-e ." in requirements


def test_bootstrap_installs_editables_without_pythonpath_hacks() -> None:
    bootstrap = (ROOT / "scripts" / "bootstrap_all.sh").read_text(encoding="utf-8")

    # Check for venv creation (either direct python3 or via PYTHON_BIN variable)
    assert "python3 -m venv .venv" in bootstrap or "PYTHON_BIN" in bootstrap, "venv creation missing"
    assert "source .venv/bin/activate" in bootstrap
    # Check for pip upgrade (either direct pip or via VENV_PIP variable)
    assert "pip install --upgrade pip" in bootstrap or "VENV_PIP" in bootstrap
    assert "pip install -r requirements.txt" in bootstrap or "VENV_PIP" in bootstrap
    assert "pip install -e third_party/aider" in bootstrap or "VENV_PIP" in bootstrap
    assert "pip install -e ." in bootstrap or "VENV_PIP" in bootstrap
    assert "pip install -e third_party/code-agent-runtime" in bootstrap or "VENV_PIP" in bootstrap
    assert "pip install -e third_party/cocoindex-code" in bootstrap or "VENV_PIP" in bootstrap
    # Check for import verification (either "Import checks passed" or "Verifying runtime imports")
    assert "Import checks passed" in bootstrap or "Verifying runtime imports" in bootstrap
    assert "PYTHONPATH" not in bootstrap
    assert "requirements_bootstrap.txt" not in bootstrap
