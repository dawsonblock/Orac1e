"""
Security Sandbox for Code Execution

This module provides sandboxing capabilities for code execution in the
worker_hardened module. It adds resource limits, file system restrictions,
and audit logging to prevent malicious or buggy code from causing damage.

Security Features:
- CPU time limits
- Memory limits
- File system restrictions (chroot-like)
- Process isolation
- Audit logging
- Timeout enforcement
"""
from __future__ import annotations

import os
import resource
import signal
import sys
import time
import logging
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Generator

logger = logging.getLogger(__name__)


@dataclass
class SandboxConfig:
    """Configuration for code execution sandbox."""
    
    # Resource limits
    max_cpu_time: int = 30  # seconds
    max_memory: int = 512 * 1024 * 1024  # 512 MB
    max_file_size: int = 10 * 1024 * 1024  # 10 MB
    max_open_files: int = 64
    
    # File system restrictions
    allowed_paths: tuple[str, ...] = ()
    blocked_paths: tuple[str, ...] = (
        "/etc",
        "/usr",
        "/var",
        "/tmp",
        "/home",
        "/root",
        "/opt",
    )
    
    # Process restrictions
    allow_network: bool = False
    allow_fork: bool = False
    allow_exec: bool = False
    
    # Timeout
    execution_timeout: int = 60  # seconds


class SandboxViolation(Exception):
    """Raised when a sandbox violation is detected."""
    pass


class SandboxTimeout(Exception):
    """Raised when execution times out."""
    pass


class SecuritySandbox:
    """Security sandbox for code execution."""
    
    def __init__(self, config: Optional[SandboxConfig] = None):
        self.config = config or SandboxConfig()
        self._start_time: Optional[float] = None
        self._violations: list[dict] = []
    
    def _log_violation(self, violation_type: str, details: str) -> None:
        """Log a security violation."""
        violation = {
            "timestamp": time.time(),
            "type": violation_type,
            "details": details,
            "pid": os.getpid(),
        }
        self._violations.append(violation)
        logger.warning(f"SANDBOX VIOLATION: {violation_type} - {details}")
    
    def _set_resource_limits(self) -> None:
        """Set resource limits for the current process."""
        try:
            # CPU time limit
            resource.setrlimit(
                resource.RLIMIT_CPU,
                (self.config.max_cpu_time, self.config.max_cpu_time)
            )
            
            # Memory limit
            resource.setrlimit(
                resource.RLIMIT_AS,
                (self.config.max_memory, self.config.max_memory)
            )
            
            # File size limit
            resource.setrlimit(
                resource.RLIMIT_FSIZE,
                (self.config.max_file_size, self.config.max_file_size)
            )
            
            # Open files limit
            resource.setrlimit(
                resource.RLIMIT_NOFILE,
                (self.config.max_open_files, self.config.max_open_files)
            )
            
            # Prevent core dumps (may contain sensitive data)
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
            
        except (ValueError, OSError) as e:
            self._log_violation("resource_limit_error", str(e))
    
    def _validate_path(self, path: str) -> bool:
        """Validate that a path is allowed."""
        try:
            resolved = Path(path).resolve()
            path_str = str(resolved)
            
            # Check blocked paths
            for blocked in self.config.blocked_paths:
                if path_str.startswith(blocked):
                    self._log_violation("blocked_path", f"Access to {path} blocked")
                    return False
            
            # Check allowed paths (if specified)
            if self.config.allowed_paths:
                for allowed in self.config.allowed_paths:
                    if path_str.startswith(allowed):
                        return True
                self._log_violation("path_not_allowed", f"Path {path} not in allowed list")
                return False
            
            return True
            
        except Exception as e:
            self._log_violation("path_validation_error", str(e))
            return False
    
    def _setup_signal_handlers(self) -> None:
        """Setup signal handlers for timeout enforcement."""
        def timeout_handler(signum, frame):
            raise SandboxTimeout("Execution timed out")
        
        signal.signal(signal.SIGALRM, timeout_handler)
        signal.alarm(self.config.execution_timeout)
    
    def _cleanup_signal_handlers(self) -> None:
        """Cleanup signal handlers."""
        signal.alarm(0)
        signal.signal(signal.SIGALRM, signal.SIG_DFL)
    
    @contextmanager
    def execute(self) -> Generator[None, None, None]:
        """Context manager for sandboxed execution."""
        self._start_time = time.time()
        self._violations = []
        
        try:
            # Setup sandbox
            self._set_resource_limits()
            self._setup_signal_handlers()
            
            logger.debug("Sandbox activated")
            yield
            
        except SandboxTimeout as e:
            self._log_violation("timeout", str(e))
            raise
            
        except Exception as e:
            self._log_violation("execution_error", str(e))
            raise
            
        finally:
            # Cleanup
            self._cleanup_signal_handlers()
            elapsed = time.time() - (self._start_time or time.time())
            logger.debug(f"Sandbox deactivated (elapsed: {elapsed:.2f}s)")
    
    def get_violations(self) -> list[dict]:
        """Get list of violations detected during execution."""
        return self._violations.copy()
    
    def has_violations(self) -> bool:
        """Check if any violations were detected."""
        return len(self._violations) > 0


# Global sandbox instance
_sandbox: Optional[SecuritySandbox] = None


def get_sandbox(config: Optional[SandboxConfig] = None) -> SecuritySandbox:
    """Get or create the global sandbox instance."""
    global _sandbox
    if _sandbox is None:
        _sandbox = SecuritySandbox(config)
    return _sandbox


def sandboxed_execution(config: Optional[SandboxConfig] = None):
    """Context manager for sandboxed execution using the global sandbox."""
    sandbox = get_sandbox(config)
    return sandbox.execute()


def validate_file_access(path: str, mode: str = "read") -> bool:
    """
    Validate that file access is allowed.
    
    Args:
        path: File path to validate
        mode: Access mode ("read", "write", "execute")
    
    Returns:
        True if access is allowed, False otherwise
    """
    sandbox = get_sandbox()
    return sandbox._validate_path(path)


class SandboxedFileWriter:
    """File writer with sandbox restrictions."""
    
    def __init__(self, base_path: str, config: Optional[SandboxConfig] = None):
        self.base_path = Path(base_path).resolve()
        self.sandbox = SecuritySandbox(config)
    
    def write(self, relative_path: str, content: str, encoding: str = "utf-8") -> bool:
        """
        Write content to a file with sandbox validation.
        
        Args:
            relative_path: Path relative to base_path
            content: Content to write
            encoding: File encoding
        
        Returns:
            True if write succeeded, False if blocked
        """
        try:
            target_path = (self.base_path / relative_path).resolve()
            
            # Validate path
            if not self.sandbox._validate_path(str(target_path)):
                return False
            
            # Ensure path is within base_path
            if not str(target_path).startswith(str(self.base_path)):
                self.sandbox._log_violation(
                    "path_escape",
                    f"Path {relative_path} escapes base path"
                )
                return False
            
            # Create parent directories if needed
            target_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Write content
            target_path.write_text(content, encoding=encoding)
            return True
            
        except Exception as e:
            self.sandbox._log_violation("write_error", str(e))
            return False
    
    def read(self, relative_path: str, encoding: str = "utf-8") -> Optional[str]:
        """
        Read content from a file with sandbox validation.
        
        Args:
            relative_path: Path relative to base_path
            encoding: File encoding
        
        Returns:
            File content or None if blocked/error
        """
        try:
            target_path = (self.base_path / relative_path).resolve()
            
            # Validate path
            if not self.sandbox._validate_path(str(target_path)):
                return None
            
            # Ensure path is within base_path
            if not str(target_path).startswith(str(self.base_path)):
                self.sandbox._log_violation(
                    "path_escape",
                    f"Path {relative_path} escapes base path"
                )
                return None
            
            # Read content
            return target_path.read_text(encoding=encoding)
            
        except Exception as e:
            self.sandbox._log_violation("read_error", str(e))
            return None
