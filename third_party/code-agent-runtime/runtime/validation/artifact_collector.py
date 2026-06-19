from __future__ import annotations

import json
import zipfile
from pathlib import Path

from runtime.reporting.redaction import redact_text


class ArtifactCollector:
    def __init__(self, outbox_root: Path, *, redact: bool = True):
        self.outbox_root = Path(outbox_root)
        self.outbox_root.mkdir(parents=True, exist_ok=True)
        self.redact = redact

    def _clean_text(self, content: str) -> str:
        return redact_text(content) if self.redact else content

    def write_json(self, name: str, payload: dict) -> Path:
        path = self.outbox_root / name
        text = json.dumps(payload, indent=2, sort_keys=True)
        path.write_text(self._clean_text(text), encoding='utf-8')
        return path

    def write_text(self, name: str, content: str) -> Path:
        path = self.outbox_root / name
        path.write_text(self._clean_text(content), encoding='utf-8')
        return path

    def write_bundle(self, bundle_name: str, files: dict[str, str | bytes]) -> Path:
        path = self.outbox_root / bundle_name
        with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
            for name, content in files.items():
                if isinstance(content, bytes):
                    zf.writestr(name, content)
                else:
                    zf.writestr(name, self._clean_text(content).encode('utf-8'))
        return path
