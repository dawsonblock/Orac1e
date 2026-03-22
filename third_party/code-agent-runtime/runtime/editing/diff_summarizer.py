from __future__ import annotations

from runtime.events.schemas import PatchArtifact


class DiffSummarizer:
    def summarize(self, artifact: PatchArtifact) -> str:
        return artifact.summary
