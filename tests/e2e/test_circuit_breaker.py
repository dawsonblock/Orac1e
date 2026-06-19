"""E2E tests for circuit breaker behavior.

This module tests the CircuitBreaker class from production_utils
under various failure and recovery scenarios.
"""
from __future__ import annotations

import time

import pytest

from integration.shared_py.production_utils import CircuitBreaker


class TestCircuitBreakerBasic:
    """Test basic circuit breaker functionality."""

    def test_circuit_breaker_starts_closed(self):
        """Test that circuit breaker starts in closed state."""
        cb = CircuitBreaker(failure_threshold=3)
        assert cb.can_execute() is True, "Circuit breaker should start closed"
        assert cb.state == "CLOSED"

    def test_circuit_breaker_opens_after_threshold(self):
        """Test that circuit breaker opens after failure threshold."""
        cb = CircuitBreaker(failure_threshold=3)

        for _ in range(3):
            cb.record_failure()

        assert cb.can_execute() is False, "Circuit breaker should open after threshold"
        assert cb.state == "OPEN"

    def test_circuit_breaker_tracks_failures(self):
        """Test that circuit breaker tracks failure count."""
        cb = CircuitBreaker(failure_threshold=5)

        cb.record_failure()
        cb.record_failure()

        assert cb.failures == 2, "Should track failure count"

    def test_circuit_breaker_resets_on_success(self):
        """Test that failure count resets on success."""
        cb = CircuitBreaker(failure_threshold=3)

        cb.record_failure()
        cb.record_failure()
        cb.record_success()

        assert cb.failures == 0, "Failure count should reset on success"
        assert cb.state == "CLOSED"


class TestCircuitBreakerRecovery:
    """Test circuit breaker recovery behavior."""

    def test_circuit_breaker_half_open_after_recovery_time(self):
        """Test that circuit breaker enters half-open state after recovery time."""
        cb = CircuitBreaker(failure_threshold=3, recovery_time=0.1)

        # Open the circuit breaker
        for _ in range(3):
            cb.record_failure()

        assert cb.can_execute() is False

        # Wait for recovery time
        time.sleep(0.2)

        # Should be half-open (allow one request)
        assert cb.can_execute() is True, "Circuit breaker should be half-open after recovery"
        assert cb.state == "HALF-OPEN"

    def test_circuit_breaker_closes_on_success_in_half_open(self):
        """Test that circuit breaker closes on success in half-open state."""
        cb = CircuitBreaker(failure_threshold=3, recovery_time=0.1)

        # Open the circuit breaker
        for _ in range(3):
            cb.record_failure()

        # Wait for recovery time
        time.sleep(0.2)

        # Record success in half-open state
        cb.record_success()

        # Should be closed now
        assert cb.can_execute() is True
        assert cb.failures == 0, "Failure count should reset after recovery"
        assert cb.state == "CLOSED"

    def test_circuit_breaker_reopens_on_failure_in_half_open(self):
        """Test that circuit breaker reopens on failure in half-open state."""
        cb = CircuitBreaker(failure_threshold=3, recovery_time=0.1)

        # Open the circuit breaker
        for _ in range(3):
            cb.record_failure()

        # Wait for recovery time
        time.sleep(0.2)

        # Record failure in half-open state
        cb.record_failure()

        # Should be open again
        assert cb.can_execute() is False
        assert cb.state == "OPEN"


class TestCircuitBreakerIntegration:
    """Test circuit breaker with planner integration."""

    def test_planner_uses_circuit_breaker(self):
        """Test that planner respects circuit breaker state."""
        from integration.workers_planner import planner_breaker

        # Save original state
        original_failures = planner_breaker.failures
        original_state = planner_breaker.state

        # Record failures
        for _ in range(3):
            planner_breaker.record_failure()

        # Verify circuit breaker is open
        assert planner_breaker.can_execute() is False

        # Reset by recording success
        planner_breaker.record_success()
        assert planner_breaker.can_execute() is True

    def test_circuit_breaker_prevents_execution(self):
        """Test that open circuit breaker prevents task execution."""
        from integration.workers_planner import coding_planner_execute, planner_breaker

        # Save original state
        original_failures = planner_breaker.failures
        original_state = planner_breaker.state

        # Open the circuit breaker
        for _ in range(3):
            planner_breaker.record_failure()

        # Try to execute - should fail fast
        result = coding_planner_execute("test task", "/nonexistent")

        assert result.get("success") is False
        assert result.get("error") == "CIRCUIT_BREAKER_OPEN"

        # Reset
        planner_breaker.record_success()
