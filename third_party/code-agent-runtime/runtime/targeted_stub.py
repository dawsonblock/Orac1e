from __future__ import annotations

from pathlib import Path
from typing import Mapping

from runtime.sandbox.base import CommandResult, CommandRunner


class SequenceRunner(CommandRunner):
    def __init__(self, results: list[CommandResult]):
        self.results = list(results)
        self.calls: list[list[str]] = []

    def run(self, command: list[str], *, cwd: Path, env: Mapping[str, str] | None = None, timeout_seconds: int | None = None) -> CommandResult:
        self.calls.append(list(command))
        if not self.results:
            raise AssertionError('no more stubbed command results available')
        return self.results.pop(0)
