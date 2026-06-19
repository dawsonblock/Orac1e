from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from runtime.profile.repo_profile import RepoProfileLoader
from runtime.validation.language_detection import RepoLanguageDetector

if TYPE_CHECKING:
    from runtime.validation.validation_cache import ValidationCache


class TestSelector:
    __test__ = False

    def __init__(
        self,
        profile_loader: RepoProfileLoader | None = None,
        cache: ValidationCache | None = None
    ):
        self.detector = RepoLanguageDetector()
        self.profile_loader = profile_loader or RepoProfileLoader()
        self._cache = cache
        self._mapping_cache: dict[str, list[str]] = {}

    def _iter_test_roots(self, repo_root: Path) -> list[Path]:
        profile = self.profile_loader.load(repo_root)
        roots: list[Path] = []
        configured = profile.test_paths or ['tests']
        for rel in configured:
            root = repo_root / rel
            if root.exists() and root.is_dir() and root not in roots:
                roots.append(root)
        if not roots:
            fallback = repo_root / 'tests'
            if fallback.exists() and fallback.is_dir():
                roots.append(fallback)
        return roots

    def _all_python_tests(self, repo_root: Path) -> list[str]:
        out: list[str] = []
        for tests_dir in self._iter_test_roots(repo_root):
            for path in tests_dir.rglob('test_*.py'):
                rel = str(path.relative_to(repo_root))
                if rel not in out:
                    out.append(rel)
        return sorted(out)

    def _python_candidates_for_file(self, repo_root: Path, rel: str) -> list[str]:
        path = Path(rel)
        stem = path.stem
        name = f'test_{stem}.py'
        candidates = []
        for tests_dir in self._iter_test_roots(repo_root):
            direct = tests_dir / name
            if direct.exists():
                candidates.append(str(direct.relative_to(repo_root)))
            nested = list(tests_dir.rglob(name))
            for item in nested:
                rel_item = str(item.relative_to(repo_root))
                if rel_item not in candidates:
                    candidates.append(rel_item)
            parts = path.parts
            if 'src' in parts and len(parts) > 1:
                src_index = parts.index('src')
                subparts = parts[src_index + 1:-1]
                nested_guess = tests_dir.joinpath(*subparts, name)
                if nested_guess.exists():
                    rel_guess = str(nested_guess.relative_to(repo_root))
                    if rel_guess not in candidates:
                        candidates.append(rel_guess)
        return candidates

    def _all_js_ts_tests(self, repo_root: Path) -> list[str]:
        patterns = ['*.test.js', '*.spec.js', '*.test.ts', '*.spec.ts', '*.test.tsx', '*.spec.tsx']
        out: list[str] = []
        search_roots = self._iter_test_roots(repo_root) or [repo_root]
        for root in search_roots:
            for pattern in patterns:
                for path in root.rglob(pattern):
                    rel = str(path.relative_to(repo_root))
                    if rel not in out:
                        out.append(rel)
        return sorted(out)

    def _js_ts_candidates_for_file(self, repo_root: Path, rel: str) -> list[str]:
        path = Path(rel)
        stem = path.stem
        base = stem.replace('.test', '').replace('.spec', '')
        patterns = [f'{base}.test.js', f'{base}.spec.js', f'{base}.test.ts', f'{base}.spec.ts', f'{base}.test.tsx', f'{base}.spec.tsx']
        out: list[str] = []
        search_roots = self._iter_test_roots(repo_root) or [repo_root]
        for root in search_roots:
            for pattern in patterns:
                for item in root.rglob(pattern):
                    rel_item = str(item.relative_to(repo_root))
                    if rel_item not in out:
                        out.append(rel_item)
        return out

    def _all_rust_tests(self, repo_root: Path) -> list[str]:
        out: list[str] = []
        for tests_dir in self._iter_test_roots(repo_root):
            for path in tests_dir.glob('*.rs'):
                if path.stem not in out:
                    out.append(path.stem)
        return sorted(out)

    def _rust_candidates_for_file(self, repo_root: Path, rel: str) -> list[str]:
        stem = Path(rel).stem
        matches = []
        for tests_dir in self._iter_test_roots(repo_root):
            exact = tests_dir / f'{stem}.rs'
            if exact.exists():
                matches.append(exact.stem)
            for path in tests_dir.glob('*.rs'):
                if stem in path.stem and path.stem not in matches:
                    matches.append(path.stem)
        return matches

    def _get_all_tests(self, repo_root: Path, language: str) -> list[str]:
        """Get all tests for the repository with caching."""
        cache_key = f"{repo_root}:{language}"
        
        # Check in-memory cache first
        if cache_key in self._mapping_cache:
            return self._mapping_cache[cache_key]
        
        # Check disk cache
        if self._cache is not None:
            cached = self._cache.get_test_mapping(repo_root)
            if cached is not None:
                self._mapping_cache[cache_key] = cached
                return cached
        
        # Build the full test mapping
        if language == 'js_ts':
            tests = self._all_js_ts_tests(repo_root)
        elif language == 'rust':
            tests = self._all_rust_tests(repo_root)
        else:
            tests = self._all_python_tests(repo_root)
        
        # Cache the result
        self._mapping_cache[cache_key] = tests
        if self._cache is not None:
            self._cache.set_test_mapping(repo_root, tests)
        
        return tests

    def select(self, repo_root: Path, changed_files: list[str], explicit_tests: list[str]) -> list[str]:
        language = self.detector.detect(repo_root).primary
        selected: list[str] = []
        for test in explicit_tests:
            if language == 'rust':
                if test not in selected:
                    selected.append(test)
            elif (repo_root / test).exists() and test not in selected:
                selected.append(test)
        for rel in changed_files:
            if language == 'js_ts':
                candidates = self._js_ts_candidates_for_file(repo_root, rel)
            elif language == 'rust':
                candidates = self._rust_candidates_for_file(repo_root, rel)
            else:
                candidates = self._python_candidates_for_file(repo_root, rel)
            for candidate in candidates:
                if candidate not in selected:
                    selected.append(candidate)
        if selected:
            return selected
        # Use cached test listing fallback
        return self._get_all_tests(repo_root, language)
