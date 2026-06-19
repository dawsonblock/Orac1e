from __future__ import annotations
import json
from pathlib import Path
from .validators import verify_manifest, ManifestVerificationResult

def load_manifest(path: str | Path) -> ManifestVerificationResult:
    """
    Load and verify a tool manifest from a JSON file.
    
    Returns a ManifestVerificationResult containing validation status
    and the validated ToolManifestModel if successful.
    """
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    return verify_manifest(data)
