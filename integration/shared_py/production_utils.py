import logging
import os
import sys
import json
import time
import functools
from typing import Any, Dict

def lru_cache_with_ttl(maxsize: int = 128, ttl: int = 300):
    """LRU Cache with Time-To-Live (TTL) for expensive FS/LLM operations."""
    def decorator(func):
        @functools.lru_cache(maxsize=maxsize)
        def cached_func(*args, **kwargs):
            return {"value": func(*args, **kwargs), "time": time.time()}

        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            result = cached_func(*args, **kwargs)
            if time.time() - result["time"] > ttl:
                cached_func.cache_clear()
                result = cached_func(*args, **kwargs)
            return result["value"]
        return wrapper
    return decorator

def setup_production_logging(level=logging.INFO):
    """Sets up standardized JSON logging for production monitoring."""
    logging.basicConfig(
        level=level,
        format='{"timestamp":"%(asctime)s", "name":"%(name)s", "level":"%(levelname)s", "message":"%(message)s"}',
        datefmt='%Y-%m-%dT%H:%M:%SZ',
        stream=sys.stdout
    )

class CircuitBreaker:
    """Simple circuit breaker to avoid cascading failures in LLM/external workers."""

    def __init__(self, failure_threshold: int = 5, recovery_time: int = 60):
        self.failure_threshold = failure_threshold
        self.recovery_time = recovery_time
        self.failures = 0
        self.last_failure_time = 0
        self.state = "CLOSED"

    def can_execute(self) -> bool:
        if self.state == "OPEN":
            if time.time() - self.last_failure_time > self.recovery_time:
                self.state = "HALF-OPEN"
                return True
            return False
        return True

    def record_failure(self):
        self.failures += 1
        self.last_failure_time = time.time()
        if self.failures >= self.failure_threshold:
            self.state = "OPEN"

    def record_success(self):
        self.failures = 0
        self.state = "CLOSED"

def get_config(key: str, default: Any = None) -> Any:
    """Fetch from app.env or environment variables."""
    # Production should prioritize environment variables
    val = os.environ.get(key)
    if val:
        return val
    return default
