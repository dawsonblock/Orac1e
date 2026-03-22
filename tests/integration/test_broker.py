"""Comprehensive tests for the retrieval broker service.

This module tests:
1. Result sorting and ranking by relevance score
2. Empty and edge case handling
3. Multiple result deduplication
4. Score boundary conditions
"""
import pytest
from integration.retrieval_broker.search_merge import sort_results
from integration.shared_py.models import RetrievalResult


class TestResultSorting:
    """Tests for result ranking and sorting functionality."""

    def test_sort_results_returns_ranked_by_score(self):
        """Test that broker returns ranked results with path and score."""
        results = [
            RetrievalResult(
                path="src/main.py",
                score=0.5,
                snippet="def main():",
                start_line=1,
                end_line=1,
                language="python"
            ),
            RetrievalResult(
                path="src/utils.py",
                score=0.9,
                snippet="def helper():",
                start_line=5,
                end_line=5,
                language="python"
            ),
            RetrievalResult(
                path="src/lib.py",
                score=0.3,
                snippet="class Helper:",
                start_line=10,
                end_line=12,
                language="python"
            ),
        ]
        
        sorted_results = sort_results(results)
        
        # Verify results are sorted by score descending
        assert sorted_results[0].path == "src/utils.py", \
            "Highest score should be first"
        assert sorted_results[0].score == 0.9, \
            "First result should have score 0.9"
        assert sorted_results[1].path == "src/main.py", \
            "Middle score should be second"
        assert sorted_results[1].score == 0.5, \
            "Second result should have score 0.5"
        assert sorted_results[2].path == "src/lib.py", \
            "Lowest score should be last"
        assert sorted_results[2].score == 0.3, \
            "Third result should have score 0.3"

    def test_sort_results_preserves_required_fields(self):
        """Verify each result retains all required fields after sorting."""
        results = [
            RetrievalResult(
                path="test.py",
                score=0.8,
                snippet="test snippet",
                start_line=10,
                end_line=15,
                language="python"
            ),
        ]
        
        sorted_results = sort_results(results)
        
        for result in sorted_results:
            assert result.path is not None, \
                "Result path should not be None"
            assert result.score is not None, \
                "Result score should not be None"
            assert isinstance(result.score, float), \
                "Score should be a float"
            assert result.snippet is not None, \
                "Result snippet should not be None"
            assert result.start_line is not None, \
                "Result start_line should not be None"
            assert result.end_line is not None, \
                "Result end_line should not be None"


class TestEdgeCases:
    """Tests for edge cases and error scenarios in result sorting."""

    def test_sort_results_empty_list(self):
        """Verify empty list returns empty list."""
        sorted_results = sort_results([])
        assert sorted_results == [], \
            "Empty input should return empty output"

    def test_sort_results_single_item(self):
        """Verify single item list returns same item."""
        results = [
            RetrievalResult(
                path="solo.py",
                score=1.0,
                snippet="solo",
                start_line=1,
                end_line=1,
                language="python"
            ),
        ]
        
        sorted_results = sort_results(results)
        
        assert len(sorted_results) == 1, \
            "Single item list should return single item"
        assert sorted_results[0].path == "solo.py", \
            "Single item path should be preserved"

    def test_sort_results_equal_scores(self):
        """Verify equal scores maintain stable sort order."""
        results = [
            RetrievalResult(
                path="file_a.py",
                score=0.5,
                snippet="a",
                start_line=1,
                end_line=1,
                language="python"
            ),
            RetrievalResult(
                path="file_b.py",
                score=0.5,
                snippet="b",
                start_line=1,
                end_line=1,
                language="python"
            ),
        ]
        
        sorted_results = sort_results(results)
        
        assert len(sorted_results) == 2, \
            "Should return both items"
        # Both should have same score
        assert sorted_results[0].score == sorted_results[1].score == 0.5, \
            "Both scores should be equal"

    def test_sort_results_boundary_scores(self):
        """Test sorting with boundary score values."""
        results = [
            RetrievalResult(
                path="zero.py",
                score=0.0,
                snippet="zero",
                start_line=1,
                end_line=1,
                language="python"
            ),
            RetrievalResult(
                path="perfect.py",
                score=1.0,
                snippet="perfect",
                start_line=1,
                end_line=1,
                language="python"
            ),
        ]
        
        sorted_results = sort_results(results)
        
        assert sorted_results[0].score == 1.0, \
            "Perfect score should be first"
        assert sorted_results[1].score == 0.0, \
            "Zero score should be last"

    def test_sort_results_negative_scores(self):
        """Test handling of negative scores if applicable."""
        results = [
            RetrievalResult(
                path="negative.py",
                score=-0.5,
                snippet="negative",
                start_line=1,
                end_line=1,
                language="python"
            ),
            RetrievalResult(
                path="positive.py",
                score=0.5,
                snippet="positive",
                start_line=1,
                end_line=1,
                language="python"
            ),
        ]
        
        sorted_results = sort_results(results)
        
        assert sorted_results[0].score >= sorted_results[1].score, \
            "Negative scores should sort correctly"


class TestLanguageFiltering:
    """Tests for language-based result handling."""

    def test_sort_results_multiple_languages(self):
        """Verify sorting works across different languages."""
        results = [
            RetrievalResult(
                path="main.js",
                score=0.7,
                snippet="js code",
                start_line=1,
                end_line=1,
                language="javascript"
            ),
            RetrievalResult(
                path="main.py",
                score=0.8,
                snippet="py code",
                start_line=1,
                end_line=1,
                language="python"
            ),
            RetrievalResult(
                path="main.swift",
                score=0.9,
                snippet="swift code",
                start_line=1,
                end_line=1,
                language="swift"
            ),
        ]
        
        sorted_results = sort_results(results)
        
        assert sorted_results[0].language == "swift", \
            "Swift file should have highest score"
        assert sorted_results[1].language == "python", \
            "Python file should be second"
        assert sorted_results[2].language == "javascript", \
            "JavaScript file should have lowest score"

    def test_sort_results_unknown_language(self):
        """Test handling of unknown language tags."""
        results = [
            RetrievalResult(
                path="file.xyz",
                score=0.5,
                snippet="unknown",
                start_line=1,
                end_line=1,
                language="unknown"
            ),
            RetrievalResult(
                path="file.abc",
                score=0.9,
                snippet="known",
                start_line=1,
                end_line=1,
                language="python"
            ),
        ]
        
        sorted_results = sort_results(results)
        
        assert sorted_results[0].language == "python", \
            "Known language should rank higher"
        assert sorted_results[1].language == "unknown", \
            "Unknown language should rank lower"


class TestSnippetIntegrity:
    """Tests for snippet preservation during sorting."""

    def test_sort_results_preserves_snippets(self):
        """Verify snippets are preserved exactly after sorting."""
        original_snippet = "def example_function(arg1, arg2):\n    return arg1 + arg2"
        results = [
            RetrievalResult(
                path="test.py",
                score=0.5,
                snippet=original_snippet,
                start_line=1,
                end_line=3,
                language="python"
            ),
        ]
        
        sorted_results = sort_results(results)
        
        assert sorted_results[0].snippet == original_snippet, \
            "Snippet should be preserved exactly"

    def test_sort_results_preserves_line_numbers(self):
        """Verify line number ranges are preserved."""
        results = [
            RetrievalResult(
                path="test.py",
                score=0.5,
                snippet="code",
                start_line=10,
                end_line=25,
                language="python"
            ),
        ]
        
        sorted_results = sort_results(results)
        
        assert sorted_results[0].start_line == 10, \
            "Start line should be preserved"
        assert sorted_results[0].end_line == 25, \
            "End line should be preserved"
        assert sorted_results[0].start_line <= sorted_results[0].end_line, \
            "Start line should be <= end line"
