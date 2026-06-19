"""E2E tests for validation flow with real diffs.

This module tests the complete validation pipeline including:
- Diff generation and parsing
- Path budget enforcement
- File change validation
- End-to-end validation with real modifications
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from integration.shared_py.diff_utils import (
    enforce_path_budget,
    extract_touched_files,
    changed_line_count,
    is_path_blocked,
    normalize_repo_path,
    check_path_traversal,
    BLOCKED_PATH_PREFIXES,
)


@pytest.fixture
def repo_with_changes(tmp_path):
    """Create a repository with various file changes."""
    repo = tmp_path / "validation_repo"
    repo.mkdir()

    # Initialize git repo
    subprocess.run(["git", "init", str(repo)], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@test.com"], check=True)

    # Create initial files
    (repo / "src").mkdir()
    (repo / "tests").mkdir()
    (repo / "docs").mkdir()

    (repo / "src" / "main.py").write_text("print('hello')\n", encoding="utf-8")
    (repo / "tests" / "test_main.py").write_text("def test_hello(): pass\n", encoding="utf-8")
    (repo / "docs" / "README.md").write_text("# README\n", encoding="utf-8")

    # Commit
    subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-m", "initial"], check=True, capture_output=True)

    return repo


class TestDiffParsing:
    """Test diff parsing and extraction."""

    def test_extract_touched_files_from_diff(self):
        """Test extraction of touched files from unified diff."""
        diff_text = '''--- a/src/main.py
+++ b/src/main.py
@@ -1,3 +1,4 @@
 def hello():
+    # Added comment
     print('hello')
     return True
'''
        files = extract_touched_files(diff_text)
        assert "src/main.py" in files

    def test_extract_multiple_touched_files(self):
        """Test extraction of multiple files from diff."""
        diff_text = '''--- a/src/main.py
+++ b/src/main.py
@@ -1,3 +1,4 @@
 def hello():
+    # Added comment
     print('hello')
     return True
--- a/tests/test_main.py
+++ b/tests/test_main.py
@@ -1 +1,2 @@
 def test_hello():
+    assert True
'''
        files = extract_touched_files(diff_text)
        assert "src/main.py" in files
        assert "tests/test_main.py" in files

    def test_changed_line_count(self):
        """Test counting of changed lines."""
        diff_text = '''--- a/src/main.py
+++ b/src/main.py
@@ -1,3 +1,4 @@
 def hello():
+    # Added line 1
+    # Added line 2
     print('hello')
-    return True
+    return False
'''
        # changed_line_count returns total count of + and - lines (excluding +++ and ---)
        count = changed_line_count(diff_text)
        assert count == 4, f"Expected 4 changed lines, got {count}"


class TestPathBudgetEnforcement:
    """Test path budget enforcement."""

    def test_fail_closed_on_empty_allowlist(self):
        """Test that empty allowlist flags all files (fail-closed)."""
        diff_text = "--- a/foo.py\n+++ b/foo.py\n+x\n"
        violations = enforce_path_budget(diff_text, [])
        assert violations != [], "Empty allowlist should flag files"

    def test_path_outside_allowlist_is_violation(self):
        """Test that path outside allowed_prefixes is a violation."""
        diff_text = "--- a/src/foo.py\n+++ b/src/foo.py\n+x\n"
        violations = enforce_path_budget(diff_text, ["tests/"])
        assert violations != [], "Path outside allowed_prefixes should be violation"

    def test_blocked_path_detected(self):
        """Test that blocked paths are detected even when allowed."""
        diff_text = "--- a/.github/workflows/ci.yml\n+++ b/.github/workflows/ci.yml\n+x\n"
        violations = enforce_path_budget(diff_text, [".github/"])
        assert violations != [], "Blocked path should be detected"

    def test_valid_path_passes(self):
        """Test that valid path within allowlist passes."""
        diff_text = "--- a/src/main.py\n+++ b/src/main.py\n+x\n"
        violations = enforce_path_budget(diff_text, ["src/"])
        assert violations == [], "Valid path should pass"

    def test_path_traversal_detected(self):
        """Test that path traversal is detected via check_path_traversal."""
        # check_path_traversal calls normalize_repo_path first, which strips traversal
        # Then checks if ".." is in the normalized path parts
        # For paths like "src/../../etc/passwd", after normalization it becomes
        # "etc/passwd" (traversal is stripped), so check_path_traversal returns False
        # For paths that still have ".." after normalization, it returns True
        assert check_path_traversal("src/..") is True
        assert check_path_traversal("src/../..") is True


class TestBlockedPaths:
    """Test blocked path detection."""

    def test_git_directory_blocked(self):
        """Test that .git directory is blocked."""
        assert is_path_blocked(".git/config") is True

    def test_github_directory_blocked(self):
        """Test that .github directory is blocked."""
        assert is_path_blocked(".github/workflows/ci.yml") is True

    def test_secrets_directory_blocked(self):
        """Test that secrets directory is blocked."""
        assert is_path_blocked("secrets/api_key.txt") is True

    def test_infra_directory_blocked(self):
        """Test that infra directory is blocked."""
        assert is_path_blocked("infra/main.tf") is True

    def test_normal_path_not_blocked(self):
        """Test that normal paths are not blocked."""
        assert is_path_blocked("src/main.py") is False
        assert is_path_blocked("tests/test_main.py") is False


class TestPathNormalization:
    """Test path normalization."""

    def test_normalize_relative_path(self):
        """Test normalization of relative path."""
        result = normalize_repo_path("src/main.py")
        assert result == "src/main.py"

    def test_normalize_strips_leading_slash(self):
        """Test that leading slash is stripped (normalized)."""
        result = normalize_repo_path("/etc/passwd")
        # normalize_repo_path strips leading ./ and / characters
        assert result == "etc/passwd", "Should strip leading slash"

    def test_normalize_strips_traversal(self):
        """Test that path traversal is stripped during normalization."""
        result = normalize_repo_path("../../../etc/passwd")
        # normalize_repo_path strips leading ./ and / characters
        assert result == "etc/passwd", "Should strip traversal prefixes"

    def test_normalize_returns_none_for_dot(self):
        """Test that '.' or empty path returns None."""
        assert normalize_repo_path(".") is None
        assert normalize_repo_path("") is None


class TestEndToEndValidation:
    """End-to-end validation with real file changes."""

    def test_validate_real_patch(self, repo_with_changes):
        """Test validation of a real patch."""
        # Create a patch
        patch_text = '''--- a/src/main.py
+++ b/src/main.py
@@ -1,3 +1,4 @@
 def hello():
+    # Added comment
     print('hello')
     return True
'''

        # Extract touched files
        files = extract_touched_files(patch_text)
        assert "src/main.py" in files

        # Check path budget
        violations = enforce_path_budget(patch_text, ["src/", "tests/"])
        assert violations == [], f"Unexpected violations: {violations}"

        # Count changes
        count = changed_line_count(patch_text)
        assert count == 1, f"Expected 1 changed line, got {count}"

    def test_validate_multi_file_patch(self, repo_with_changes):
        """Test validation of a multi-file patch."""
        patch_text = '''--- a/src/main.py
+++ b/src/main.py
@@ -1,3 +1,4 @@
 def hello():
+    # Added comment
     print('hello')
     return True
--- a/tests/test_main.py
+++ b/tests/test_main.py
@@ -1 +1,2 @@
 def test_hello():
+    assert True
'''

        files = extract_touched_files(patch_text)
        assert len(files) == 2
        assert "src/main.py" in files
        assert "tests/test_main.py" in files

        violations = enforce_path_budget(patch_text, ["src/", "tests/"])
        assert violations == [], f"Unexpected violations: {violations}"

    def test_reject_patch_with_blocked_path(self, repo_with_changes):
        """Test that patch with blocked path is rejected."""
        patch_text = '''--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -1,3 +1,4 @@
 name: CI
+  # Modified workflow
 on: push
'''

        violations = enforce_path_budget(patch_text, [".github/"])
        assert violations != [], "Should reject blocked path"
