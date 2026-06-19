from __future__ import annotations

import hashlib
import json
from pathlib import Path


class DependencySnapshotter:
    CANDIDATES = [
        'pyproject.toml',
        'requirements.txt',
        'requirements-dev.txt',
        'package.json',
        'package-lock.json',
        'pnpm-lock.yaml',
        'yarn.lock',
        'Cargo.toml',
        'Cargo.lock',
    ]

    def collect(self, repo_root: Path) -> dict[str, dict[str, str | int]]:
        snapshot: dict[str, dict[str, str | int]] = {}
        for name in self.CANDIDATES:
            path = repo_root / name
            if not path.exists() or not path.is_file():
                continue
            raw = path.read_bytes()
            snapshot[name] = {
                'sha256': hashlib.sha256(raw).hexdigest(),
                'size': len(raw),
            }
        return snapshot

    def to_json(self, repo_root: Path) -> str:
        return json.dumps(self.collect(repo_root), indent=2, sort_keys=True)
