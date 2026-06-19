from __future__ import annotations

from pathlib import Path

from runtime.intake.issue_parser import ParsedIssue
from runtime.profile.repo_profile import RepoProfileLoader
from .file_ranker import FileRanker


class IssueLocalizer:
    def __init__(self, profile_loader: RepoProfileLoader | None = None):
        self.ranker = FileRanker()
        self.profile_loader = profile_loader or RepoProfileLoader()

    def _read_preview(self, path: Path) -> str:
        try:
            if path.stat().st_size > 64_000:
                return ''
            return path.read_text(encoding='utf-8')
        except Exception:
            return ''

    def _iter_test_roots(self, repo_root: Path) -> list[Path]:
        profile = self.profile_loader.load(repo_root)
        roots: list[Path] = []
        configured = profile.test_paths or ['tests']
        for rel in configured:
            root = repo_root / rel
            if root.exists() and root.is_dir() and root not in roots:
                roots.append(root)
        fallback = repo_root / 'tests'
        if fallback.exists() and fallback.is_dir() and fallback not in roots:
            roots.append(fallback)
        return roots

    def _candidate_test_targets(self, repo_root: Path, candidate_files: list[str], explicit_tests: list[str]) -> list[str]:
        if explicit_tests:
            return explicit_tests[:]
        out: list[str] = []
        test_roots = self._iter_test_roots(repo_root)
        for rel in candidate_files:
            if rel.startswith('tests/') or '/test' in rel or rel.endswith(('_test.py', 'test.py', '.spec.ts', '.test.ts', '.spec.js', '.test.js')):
                if rel not in out:
                    out.append(rel)
                continue
            stem = Path(rel).stem
            for tests_dir in test_roots:
                for pattern in [f'test_{stem}.py', f'{stem}.rs', f'{stem}.spec.ts', f'{stem}.test.ts', f'{stem}.spec.js', f'{stem}.test.js']:
                    for item in tests_dir.rglob(pattern):
                        rel_item = item.relative_to(repo_root).as_posix()
                        if rel_item not in out:
                            out.append(rel_item)
        return out

    def localize(self, repo_root: Path, parsed: ParsedIssue, limit: int = 5) -> tuple[list[str], list[str]]:
        files: list[tuple[int, str]] = []
        issue_text = parsed.title + '\n' + parsed.body
        profile = self.profile_loader.load(repo_root)
        effective_limit = parsed.max_files or profile.max_files or limit
        ignored = set(parsed.ignored_files)
        for path in repo_root.rglob('*'):
            if not path.is_file():
                continue
            rel = path.relative_to(repo_root).as_posix()
            if any(part in {'.git', '__pycache__', '.agent_outbox', '.runtime'} for part in path.parts):
                continue
            if rel in ignored or profile.is_ignored(rel):
                continue
            content = self._read_preview(path)
            score = self.ranker.score(Path(rel), issue_text, parsed, content)
            if score > 0:
                files.append((score, rel))
        files.sort(key=lambda x: (-x[0], x[1]))
        candidate_files = [path for _, path in files[:effective_limit]]
        test_targets = self._candidate_test_targets(repo_root, candidate_files, parsed.tests)
        return candidate_files, test_targets
