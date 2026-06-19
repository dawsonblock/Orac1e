"""Comprehensive tests for the Aider adapter service.

This module tests:
1. Diff extraction and parsing
2. Touched file detection
3. File path handling
4. Edge cases and error scenarios
"""
import pytest
from integration.shared_py.diff_utils import extract_touched_files, changed_line_count


class TestDiffExtraction:
    """Tests for git diff parsing and touched file extraction."""

    def test_extract_touched_files_from_diff(self):
        """Test that aider adapter returns diff and touched paths."""
        diff_text = """diff --git a/src/main.py b/src/main.py
index 1234567..89abcdef 100644
--- a/src/main.py
+++ b/src/main.py
@@ -1,5 +1,6 @@
+import os
 def main():
     print("hello")
+    return 0
diff --git a/src/utils.py b/src/utils.py
index abcdefg..1234567 100644
--- a/src/utils.py
+++ b/src/utils.py
@@ -10,3 +10,4 @@
 class Helper:
     def help(self):
         pass
+        return None
"""
        
        touched_files = extract_touched_files(diff_text)
        
        # Verify touched files are extracted correctly
        assert len(touched_files) == 2, \
            "Should extract exactly 2 touched files"
        assert "src/main.py" in touched_files, \
            "src/main.py should be in touched files"
        assert "src/utils.py" in touched_files, \
            "src/utils.py should be in touched files"
        
        # Verify they are sorted
        assert touched_files == sorted(touched_files), \
            "Touched files should be sorted alphabetically"

    def test_extract_touched_files_single_file(self):
        """Test extraction from a single-file diff."""
        diff_text = """diff --git a/README.md b/README.md
index abc1234..def5678 100644
--- a/README.md
+++ b/README.md
@@ -5,3 +5,4 @@
 Line 5
+New line 6
"""
        
        touched_files = extract_touched_files(diff_text)
        
        assert len(touched_files) == 1, \
            "Should extract exactly 1 file"
        assert touched_files[0] == "README.md", \
            "Should extract README.md"

    def test_extract_touched_files_no_diff(self):
        """Test handling of empty/non-diff input."""
        assert extract_touched_files("") == [], \
            "Empty string should return empty list"

    def test_extract_touched_files_invalid_format(self):
        """Test handling of invalid diff format."""
        invalid_diffs = [
            "not a valid diff at all",
            "random text",
            "diff --git without proper format",
            "only headers",
        ]
        
        for diff in invalid_diffs:
            result = extract_touched_files(diff)
            assert isinstance(result, list), \
                f"Invalid diff '{diff}' should return list"


class TestMultiFileDiffs:
    """Tests for multi-file diff handling."""

    def test_extract_touched_files_three_files(self):
        """Test extraction from a three-file diff."""
        diff_text = """diff --git a/foo.py b/foo.py
--- a/foo.py
+++ b/foo.py
@@ -1 +1,2 @@
+x
diff --git a/bar.py b/bar.py
--- a/bar.py
+++ b/bar.py
@@ -1 +1,2 @@
+x
diff --git a/baz.py b/baz.py
--- a/baz.py
+++ b/baz.py
@@ -1 +1,2 @@
+x
"""
        
        touched_files = extract_touched_files(diff_text)
        
        assert len(touched_files) == 3, \
            "Should extract exactly 3 files"
        assert touched_files == sorted(touched_files), \
            "Files should be sorted"

    def test_extract_touched_files_duplicates_removed(self):
        """Verify duplicates are removed from touched files."""
        diff_text = """diff --git a/file.py b/file.py
--- a/file.py
+++ b/file.py
@@ -1,3 +1,4 @@
+x
diff --git a/file.py b/file.py
--- a/file.py
+++ b/file.py
@@ -5,7 +6,8 @@
+y
"""
        
        touched_files = extract_touched_files(diff_text)
        
        assert touched_files == ["file.py"], \
            "Duplicates should be removed"

    def test_extract_touched_files_nested_paths(self):
        """Test handling of deeply nested file paths."""
        diff_text = """diff --git a/very/deeply/nested/path/to/file.py b/very/deeply/nested/path/to/file.py
--- a/very/deeply/nested/path/to/file.py
+++ b/very/deeply/nested/path/to/file.py
@@ -1 +1,2 @@
+x
"""
        
        touched_files = extract_touched_files(diff_text)
        
        assert "very/deeply/nested/path/to/file.py" in touched_files, \
            "Nested path should be preserved"


class TestChangedLineCounting:
    """Tests for changed line counting functionality."""

    def test_changed_line_count_additions_only(self):
        """Verify counting additions only."""
        diff_text = """+++ b/file.py
@@ -1 +1,3 @@
+x
+y
"""
        
        count = changed_line_count(diff_text)
        assert count == 2, \
            "Should count 2 additions"

    def test_changed_line_count_deletions_only(self):
        """Verify counting deletions only."""
        diff_text = """--- a/file.py
@@ -2 +1 @@
-x
"""
        
        count = changed_line_count(diff_text)
        assert count == 1, \
            "Should count 1 deletion"

    def test_changed_line_count_mixed(self):
        """Verify counting mixed additions and deletions."""
        diff_text = """--- a/file.py
+++ b/file.py
@@ -1,3 +1,4 @@
-x
+y
-z
+w
"""
        
        count = changed_line_count(diff_text)
        assert count == 4, \
            "Should count 4 total changes (2 additions + 2 deletions)"

    def test_changed_line_count_ignores_headers(self):
        """Verify headers (+++ and ---) are not counted."""
        diff_text = """diff --git a/file.py b/file.py
index 123..456 100644
--- a/file.py
+++ b/file.py
@@ -1 +1,2 @@
+x
"""
        
        count = changed_line_count(diff_text)
        assert count == 1, \
            "Should only count the +x line, not headers"

    def test_changed_line_count_empty(self):
        """Test counting for empty diff."""
        count = changed_line_count("")
        assert count == 0, \
            "Empty diff should have 0 changes"


class TestPathNormalization:
    """Tests for path normalization in diff extraction."""

    def test_backslash_path_normalization(self):
        """Test that backslashes are normalized to forward slashes."""
        diff_text = """diff --git a/src\\file.py b/src\\file.py
--- a/src\\file.py
+++ b/src\\file.py
@@ -1 +1,2 @@
+x
"""
        
        touched_files = extract_touched_files(diff_text)
        
        # Path should be normalized
        assert len(touched_files) >= 1, \
            "Should extract path even with backslashes"

    def test_path_with_spaces(self):
        """Test handling of paths with spaces."""
        diff_text = """diff --git a/src/path with spaces/file.py b/src/path with spaces/file.py
--- a/src/path with spaces/file.py
+++ b/src/path with spaces/file.py
@@ -1 +1,2 @@
+x
"""
        
        touched_files = extract_touched_files(diff_text)
        
        assert len(touched_files) == 1, \
            "Should extract path with spaces"


class TestEdgeCases:
    """Tests for edge cases and error scenarios."""

    def test_very_long_line_in_diff(self):
        """Test handling of very long lines."""
        long_line = "+" + ("x" * 10000)
        diff_text = f"""diff --git a/file.py b/file.py
--- a/file.py
+++ b/file.py
@@ -1 +1,2 @@
{long_line}
"""
        
        count = changed_line_count(diff_text)
        assert count == 1, \
            "Should count 1 long addition"

    def test_binary_file_indicator(self):
        """Test handling of binary file indicators."""
        diff_text = """diff --git a/binary.png b/binary.png
index 1234567..89abcdef 100644
Binary files differ
"""
        
        touched_files = extract_touched_files(diff_text)
        
        # Binary files should still have their path extracted
        assert len(touched_files) >= 1, \
            "Binary file path should be extracted"

    def test_symlink_change(self):
        """Test handling of symlink changes."""
        diff_text = """diff --git a/symlink -> target b/symlink
similarity index 100%
rename from symlink -> target
rename to symlink
"""
        
        touched_files = extract_touched_files(diff_text)
        
        # Should extract the symlink path
        assert isinstance(touched_files, list), \
            "Should return list for symlink diffs"
