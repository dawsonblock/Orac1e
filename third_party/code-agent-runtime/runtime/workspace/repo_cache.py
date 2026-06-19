from __future__ import annotations

import subprocess
from pathlib import Path
from urllib.parse import urlparse

from runtime.common.result import Result


class RepoCache:
    def __init__(self, cache_root: Path):
        self.cache_root = Path(cache_root)
        self.cache_root.mkdir(parents=True, exist_ok=True)

    def _repo_dir(self, repo_url: str) -> Path:
        parsed = urlparse(repo_url)
        name = Path(parsed.path).stem or "repo"
        return self.cache_root / name

    def ensure_repo_cached(self, repo_url: str) -> Path:
        repo_dir = self._repo_dir(repo_url)
        if not repo_dir.exists():
            subprocess.run(["git", "clone", "--no-tags", repo_url, str(repo_dir)], check=True, capture_output=True, text=True)
        return repo_dir

    def fetch_ref(self, repo_dir: Path, ref: str) -> Result:
        try:
            subprocess.run(["git", "-C", str(repo_dir), "fetch", "origin", ref], check=True, capture_output=True, text=True)
            return Result(True, "ok", f"fetched {ref}")
        except subprocess.CalledProcessError as exc:
            return Result(False, "git_fetch_failed", exc.stderr or exc.stdout or str(exc))
