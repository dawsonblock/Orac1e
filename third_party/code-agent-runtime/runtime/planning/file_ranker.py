from __future__ import annotations

import re
from pathlib import Path

from runtime.intake.issue_parser import ParsedIssue


class FileRanker:
    def __init__(self):
        self._token_re = re.compile(r'[A-Za-z_][A-Za-z0-9_]{2,}')

    def _path_tokens(self, path: Path) -> set[str]:
        values: set[str] = set()
        for part in path.parts:
            for token in re.split(r'[^A-Za-z0-9_]+', part.lower()):
                if token:
                    values.add(token)
        return values

    def score(self, path: Path, issue_text: str, parsed: ParsedIssue, content: str = '') -> int:
        path_str = path.as_posix()
        path_name = path.name
        issue_lower = issue_text.lower()
        score = 0

        if path_str in parsed.ignored_files or path_name in parsed.ignored_files:
            return -10_000

        if path_str in parsed.explicit_files or path_name in parsed.explicit_files:
            score += 150
        if path_str in parsed.stacktrace_files or path_name in parsed.stacktrace_files:
            score += 100
        if path_name.lower() in issue_lower:
            score += 30

        path_tokens = self._path_tokens(path)
        issue_tokens = set(self._token_re.findall(issue_lower))
        overlap = len(path_tokens & issue_tokens)
        score += overlap * 6

        for term in parsed.search_terms:
            term_lower = term.lower()
            if term_lower in path_str.lower():
                score += 18
            if content and term_lower in content.lower():
                score += 10

        for symbol in parsed.symbol_names:
            pattern = rf'\b{re.escape(symbol)}\b'
            if re.search(pattern, path_name):
                score += 25
            if content and re.search(pattern, content):
                score += 35

        lowered = path_str.lower()
        if any(tok in lowered for tok in ['test', 'spec']):
            score += 4
        if lowered.endswith(('.py', '.js', '.ts', '.tsx', '.rs')):
            score += 2
        if any(tok in lowered for tok in ['readme', 'license', 'package-lock', 'poetry.lock']):
            score -= 8
        if any(tok in lowered for tok in ['vendor/', 'node_modules/', '.git/']):
            score -= 50
        return score
