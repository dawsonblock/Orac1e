from __future__ import annotations

import difflib
import re
from dataclasses import dataclass
from pathlib import Path

from runtime.common.ids import patch_id
from runtime.events.schemas import EditPlan, PatchArtifact
from runtime.intake.issue_parser import ParsedIssue


class PatchBuildError(ValueError):
    pass


@dataclass(frozen=True)
class PatchCandidate:
    artifact: PatchArtifact
    relpath: str
    before: str
    after: str
    strategy: str
    score: int


class PatchBuilder:
    def _make_candidate(self, *, rel: str, plan: EditPlan, before: str, after: str, strategy: str, rationale: str, added_tests: list[str]) -> PatchCandidate:
        diff = ''.join(difflib.unified_diff(
            before.splitlines(keepends=True),
            after.splitlines(keepends=True),
            fromfile=rel,
            tofile=rel,
        ))
        pid = patch_id(plan.attempt_id, [rel, strategy])
        artifact = PatchArtifact(
            task_id=plan.task_id,
            attempt_id=plan.attempt_id,
            patch_id=pid,
            diff_text=diff,
            changed_files=[rel],
            added_tests=added_tests,
            rationale=rationale,
            summary=f'Changed {rel} using {strategy}',
        )
        score = 100
        if strategy == 'regex_replace':
            score -= 5
        elif strategy == 'function_return_replace':
            score -= 4
        elif strategy == 'insert_before' or strategy == 'insert_after':
            score -= 3
        elif strategy == 'append_text':
            score -= 6
        elif strategy == 'fuzzy_line_replace':
            score -= 10
        if added_tests:
            score += 10
        return PatchCandidate(artifact=artifact, relpath=rel, before=before, after=after, strategy=strategy, score=score)

    def _read_file(self, repo_root: Path, rel: str) -> str | None:
        path = repo_root / rel
        if not path.exists() or not path.is_file():
            return None
        return path.read_text(encoding='utf-8')

    def _literal_candidate(self, repo_root: Path, rel: str, plan: EditPlan, parsed: ParsedIssue) -> PatchCandidate | None:
        if not parsed.replace_text or parsed.with_text is None:
            return None
        before = self._read_file(repo_root, rel)
        if before is None or parsed.replace_text not in before:
            return None
        count = -1 if parsed.replace_all else 1
        after = before.replace(parsed.replace_text, parsed.with_text, count)
        return self._make_candidate(
            rel=rel,
            plan=plan,
            before=before,
            after=after,
            strategy='literal_replace',
            rationale='literal replacement from issue body',
            added_tests=[],
        )

    def _regex_candidate(self, repo_root: Path, rel: str, plan: EditPlan, parsed: ParsedIssue) -> PatchCandidate | None:
        if not parsed.regex_pattern or parsed.with_text is None:
            return None
        before = self._read_file(repo_root, rel)
        if before is None:
            return None
        count_limit = 0 if parsed.replace_all else 1
        after, count = re.subn(parsed.regex_pattern, parsed.with_text, before, count=count_limit, flags=re.MULTILINE)
        if count == 0 or after == before:
            return None
        return self._make_candidate(
            rel=rel,
            plan=plan,
            before=before,
            after=after,
            strategy='regex_replace',
            rationale='regex replacement from issue body',
            added_tests=[],
        )

    def _insert_before_candidate(self, repo_root: Path, rel: str, plan: EditPlan, parsed: ParsedIssue) -> PatchCandidate | None:
        if not parsed.insert_before or parsed.with_text is None:
            return None
        before = self._read_file(repo_root, rel)
        if before is None or parsed.insert_before not in before:
            return None
        anchor = parsed.insert_before
        payload = parsed.with_text
        after = before.replace(anchor, payload + ('\n' if payload and not payload.endswith('\n') else '') + anchor, 1)
        if after == before:
            return None
        return self._make_candidate(
            rel=rel,
            plan=plan,
            before=before,
            after=after,
            strategy='insert_before',
            rationale='inserted content before anchor from issue body',
            added_tests=[],
        )

    def _insert_after_candidate(self, repo_root: Path, rel: str, plan: EditPlan, parsed: ParsedIssue) -> PatchCandidate | None:
        if not parsed.insert_after or parsed.with_text is None:
            return None
        before = self._read_file(repo_root, rel)
        if before is None or parsed.insert_after not in before:
            return None
        anchor = parsed.insert_after
        payload = parsed.with_text
        insert = anchor + ('\n' if not anchor.endswith('\n') else '') + payload
        if payload and not payload.endswith('\n'):
            insert += '\n'
        after = before.replace(anchor, insert, 1)
        if after == before:
            return None
        return self._make_candidate(
            rel=rel,
            plan=plan,
            before=before,
            after=after,
            strategy='insert_after',
            rationale='inserted content after anchor from issue body',
            added_tests=[],
        )

    def _append_text_candidate(self, repo_root: Path, rel: str, plan: EditPlan, parsed: ParsedIssue) -> PatchCandidate | None:
        if not parsed.append_text:
            return None
        before = self._read_file(repo_root, rel)
        if before is None or parsed.append_text in before:
            return None
        suffix = parsed.append_text
        after = before + ('' if not before or before.endswith('\n') else '\n') + suffix + ('' if suffix.endswith('\n') else '\n')
        return self._make_candidate(
            rel=rel,
            plan=plan,
            before=before,
            after=after,
            strategy='append_text',
            rationale='appended content from issue body',
            added_tests=[],
        )

    def _function_return_candidate(self, repo_root: Path, rel: str, plan: EditPlan, parsed: ParsedIssue) -> PatchCandidate | None:
        if not parsed.target_function or parsed.with_text is None or not rel.endswith('.py'):
            return None
        before = self._read_file(repo_root, rel)
        if before is None:
            return None
        lines = before.splitlines()
        if not lines:
            return None
        function_re = re.compile(rf'^(?P<indent>\s*)def\s+{re.escape(parsed.target_function)}\s*\(')
        function_index = None
        function_indent = ''
        for idx, line in enumerate(lines):
            match = function_re.match(line)
            if match:
                function_index = idx
                function_indent = match.group('indent')
                break
        if function_index is None:
            return None
        target_idx = None
        for idx in range(function_index + 1, len(lines)):
            line = lines[idx]
            stripped = line.strip()
            if stripped and len(line) - len(line.lstrip()) <= len(function_indent) and not stripped.startswith('#'):
                break
            if stripped.startswith('return '):
                target_idx = idx
                break
        if target_idx is None:
            return None
        line = lines[target_idx]
        indent = line[: len(line) - len(line.lstrip())]
        replacement = parsed.with_text.strip()
        if not replacement.startswith('return'):
            replacement = 'return ' + replacement
        lines[target_idx] = indent + replacement
        newline = '\n' if before.endswith('\n') else ''
        after = '\n'.join(lines) + newline
        if after == before:
            return None
        return self._make_candidate(
            rel=rel,
            plan=plan,
            before=before,
            after=after,
            strategy='function_return_replace',
            rationale=f'rewrote first return inside {parsed.target_function}',
            added_tests=[],
        )

    def _fuzzy_line_candidate(self, repo_root: Path, rel: str, plan: EditPlan, parsed: ParsedIssue) -> PatchCandidate | None:
        if not parsed.replace_text or parsed.with_text is None:
            return None
        before = self._read_file(repo_root, rel)
        if before is None or parsed.replace_text in before:
            return None
        needle = parsed.replace_text.strip()
        best_score = 0.0
        best_line = None
        lines = before.splitlines()
        for idx, line in enumerate(lines):
            score = difflib.SequenceMatcher(a=needle, b=line.strip()).ratio()
            if score > best_score:
                best_score = score
                best_line = idx
        if best_line is None or best_score < 0.72:
            return None
        prefix = lines[best_line][: len(lines[best_line]) - len(lines[best_line].lstrip())]
        replacement = parsed.with_text
        if replacement and replacement == replacement.lstrip() and prefix and '\n' not in replacement:
            replacement = prefix + replacement
        lines[best_line] = replacement
        newline = '\n' if before.endswith('\n') else ''
        after = '\n'.join(lines) + newline
        return self._make_candidate(
            rel=rel,
            plan=plan,
            before=before,
            after=after,
            strategy='fuzzy_line_replace',
            rationale=f'fuzzy line replacement from issue body (score={best_score:.2f})',
            added_tests=[],
        )

    def _test_file_candidate(self, repo_root: Path, rel: str, plan: EditPlan, parsed: ParsedIssue) -> PatchCandidate | None:
        if not parsed.add_test_file or parsed.add_test_content is None:
            return None
        if rel != parsed.add_test_file:
            return None
        path = repo_root / rel
        before = path.read_text(encoding='utf-8') if path.exists() else ''
        if parsed.add_test_content in before:
            return None
        after = before + ('' if not before or before.endswith('\n') else '\n') + parsed.add_test_content + ('\n' if not parsed.add_test_content.endswith('\n') else '')
        return self._make_candidate(
            rel=rel,
            plan=plan,
            before=before,
            after=after,
            strategy='append_test_content',
            rationale='appended test content from issue body',
            added_tests=[rel],
        )

    def preview_candidates(self, repo_root: Path, plan: EditPlan, parsed: ParsedIssue) -> list[PatchCandidate]:
        candidate_paths = list(dict.fromkeys(plan.candidate_files + ([parsed.add_test_file] if parsed.add_test_file else [])))
        candidates: list[PatchCandidate] = []
        builders = (
            self._literal_candidate,
            self._regex_candidate,
            self._insert_before_candidate,
            self._insert_after_candidate,
            self._append_text_candidate,
            self._function_return_candidate,
            self._fuzzy_line_candidate,
            self._test_file_candidate,
        )
        for rel in candidate_paths:
            for builder in builders:
                candidate = builder(repo_root, rel, plan, parsed)
                if candidate is not None:
                    candidates.append(candidate)
        candidates.sort(key=lambda item: (-item.score, item.relpath, item.strategy))
        return candidates

    def apply_candidate(self, repo_root: Path, candidate: PatchCandidate) -> None:
        path = repo_root / candidate.relpath
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(candidate.after, encoding='utf-8')

    def build(self, repo_root: Path, plan: EditPlan, parsed: ParsedIssue) -> PatchArtifact:
        candidates = self.preview_candidates(repo_root, plan, parsed)
        if not candidates:
            raise PatchBuildError('replacement target not found in candidate files')
        candidate = candidates[0]
        self.apply_candidate(repo_root, candidate)
        return candidate.artifact
