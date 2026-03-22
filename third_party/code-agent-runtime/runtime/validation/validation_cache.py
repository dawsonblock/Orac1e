from __future__ import annotations

import hashlib
import json
import logging
from pathlib import Path
from typing import Optional

from runtime.common.result import Result

logger = logging.getLogger(__name__)


class ValidationCache:
    """
    Cache for validation results to avoid redundant computation.
    
    Supports caching for:
    - Lint results (based on file hashes and language)
    - Test selection mappings (based on test directory structure)
    """
    
    def __init__(self, cache_dir: Optional[Path] = None):
        self.cache_dir = cache_dir or (Path.home() / '.cache' / 'oracle-validation')
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self._lint_cache: dict[str, dict] = {}
        self._test_mapping_cache: dict[str, list[str]] = {}
    
    def _file_hash(self, filepath: Path) -> str:
        """Compute MD5 hash of file contents."""
        if not filepath.exists():
            return ''
        return hashlib.md5(filepath.read_bytes()).hexdigest()
    
    def _build_lint_cache_key(self, repo_root: Path, changed_files: list[str], lang: str) -> tuple[str, dict[str, float]]:
        """Build cache key for lint results based on file hashes and modification times.
        
        Returns:
            Tuple of (cache_key, file_mtimes_dict) for invalidation checking
        """
        hashes = sorted(self._file_hash(repo_root / f) for f in changed_files if (repo_root / f).exists())
        combined = ''.join(hashes) + lang
        key = hashlib.md5(combined.encode()).hexdigest()
        # Capture modification times for invalidation
        file_mtimes = {}
        for f in changed_files:
            filepath = repo_root / f
            if filepath.exists():
                file_mtimes[f] = filepath.stat().st_mtime
        return key, file_mtimes
    
    def _build_test_mapping_key(self, repo_root: Path) -> str:
        """Build cache key for test selection based on test directory structure."""
        # Find all test directories
        test_patterns = ['**/test_*.py', '**/*_test.py', '**/tests/', '**/test/']
        test_files = []
        for pattern in test_patterns:
            test_files.extend(repo_root.glob(pattern))
        test_dirs = sorted(str(f.parent) for f in test_files)
        combined = ''.join(test_dirs)
        return hashlib.md5(combined.encode()).hexdigest()
    
    # Lint result caching
    def get_lint(self, repo_root: Path, changed_files: list[str], lang: str) -> Optional[Result]:
        """Get cached lint result if available and still valid."""
        key, current_mtimes = self._build_lint_cache_key(repo_root, changed_files, lang)
        
        if key in self._lint_cache:
            cached = self._lint_cache[key]
            # Check if any file has been modified since cache was created
            cached_mtimes = cached.get('file_mtimes', {})
            if self._is_cache_stale(current_mtimes, cached_mtimes):
                logger.debug(f"Cache invalidated for key {key}: file modification detected")
                del self._lint_cache[key]
            else:
                return Result(
                    ok=cached['ok'],
                    code=cached['code'],
                    message=cached['message'],
                    data=cached.get('data')
                )
        
        # Check disk cache
        cache_file = self.cache_dir / f"lint_{key}.json"
        if cache_file.exists():
            try:
                cached = json.loads(cache_file.read_text())
                # Check if any file has been modified since cache was created
                cached_mtimes = cached.get('file_mtimes', {})
                if self._is_cache_stale(current_mtimes, cached_mtimes):
                    logger.debug(f"Disk cache invalidated for key {key}: file modification detected")
                    cache_file.unlink(missing_ok=True)
                else:
                    self._lint_cache[key] = cached
                    return Result(
                        ok=cached['ok'],
                        code=cached['code'],
                        message=cached['message'],
                        data=cached.get('data')
                    )
            except (json.JSONDecodeError, KeyError):
                pass
        
        return None
    
    def _is_cache_stale(self, current_mtimes: dict[str, float], cached_mtimes: dict[str, float]) -> bool:
        """Check if any file has been modified since cache was created."""
        for filepath, cached_mtime in cached_mtimes.items():
            current_mtime = current_mtimes.get(filepath)
            if current_mtime is None:
                # File was removed - cache is stale
                return True
            if current_mtime > cached_mtime:
                # File was modified after cache was created - cache is stale
                return True
        return False
    
    def set_lint(self, repo_root: Path, changed_files: list[str], lang: str, result: Result):
        """Cache lint result."""
        key, file_mtimes = self._build_lint_cache_key(repo_root, changed_files, lang)
        cached = {
            'ok': result.ok,
            'code': result.code,
            'message': result.message,
            'data': result.data,
            'file_mtimes': file_mtimes,
        }
        
        # Memory cache
        self._lint_cache[key] = cached
        
        # Disk cache
        cache_file = self.cache_dir / f"lint_{key}.json"
        try:
            cache_file.write_text(json.dumps(cached))
        except OSError:
            pass  # Ignore cache write failures
    
    def invalidate_lint(self, repo_root: Path, changed_files: list[str], lang: str):
        """Invalidate lint cache for specific files."""
        key, _ = self._build_lint_cache_key(repo_root, changed_files, lang)
        self._lint_cache.pop(key, None)
        (self.cache_dir / f"lint_{key}.json").unlink(missing_ok=True)
    
    # Test selection caching
    def get_test_mapping(self, repo_root: Path) -> Optional[list[str]]:
        """Get cached test mapping if available."""
        key = self._build_test_mapping_key(repo_root)
        
        if key in self._test_mapping_cache:
            return self._test_mapping_cache[key]
        
        # Check disk cache
        cache_file = self.cache_dir / f"test_mapping_{key}.json"
        if cache_file.exists():
            try:
                cached = json.loads(cache_file.read_text())
                self._test_mapping_cache[key] = cached
                return cached
            except (json.JSONDecodeError, KeyError):
                pass
        
        return None
    
    def set_test_mapping(self, repo_root: Path, mapping: list[str]):
        """Cache test mapping."""
        key = self._build_test_mapping_key(repo_root)
        
        # Memory cache
        self._test_mapping_cache[key] = mapping
        
        # Disk cache
        cache_file = self.cache_dir / f"test_mapping_{key}.json"
        try:
            cache_file.write_text(json.dumps(mapping))
        except OSError:
            pass  # Ignore cache write failures
    
    def clear(self):
        """Clear all caches."""
        self._lint_cache.clear()
        self._test_mapping_cache.clear()
        for cache_file in self.cache_dir.glob('*.json'):
            cache_file.unlink(missing_ok=True)