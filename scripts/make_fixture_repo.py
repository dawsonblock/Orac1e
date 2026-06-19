#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "workspace" / "fixtures" / "buggy-repo"

FILES: dict[str, str] = {
    ".gitignore": "__pycache__/\n.pytest_cache/\n",
    "README.md": (
        "# Buggy fixture repo\n\n"
        "This repo intentionally contains a small parser bug so the end-to-end run path can be tested quickly.\n"
    ),
    "pyproject.toml": (
        "[project]\n"
        "name = \"buggy-repo\"\n"
        "version = \"0.1.0\"\n\n"
        "[tool.pytest.ini_options]\n"
        "testpaths = [\"tests\"]\n"
    ),
    "src/parser.py": "def first_token(tokens):\n    return tokens[0]\n",
    "tests/test_parser.py": (
        "from src.parser import first_token\n\n"
        "def test_empty_tokens_returns_none():\n"
        "    assert first_token([]) is None\n"
    ),
}


def write_files() -> None:
    for relative_path, content in FILES.items():
        path = FIXTURE / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=FIXTURE,
        check=True,
        capture_output=True,
        text=True,
    )


def ensure_git_repo() -> None:
    if not (FIXTURE / ".git").exists():
        git("init", "-b", "main")
        git("config", "user.name", "Oracle Fixture")
        git("config", "user.email", "oracle-fixture@example.invalid")

    git("add", ".")
    status = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=FIXTURE,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if status:
        git("commit", "-m", "Initial fixture state")


def main() -> None:
    FIXTURE.mkdir(parents=True, exist_ok=True)
    write_files()
    ensure_git_repo()
    print(FIXTURE)


if __name__ == "__main__":
    main()
