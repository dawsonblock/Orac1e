"""
Input Validation and Sanitization Module

This module provides comprehensive input validation and sanitization
for all user-controlled inputs across the Orac1e system.

Security Features:
- Path traversal prevention
- Injection attack prevention
- Length limits
- Format validation
- Sanitization functions
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Optional, Tuple


class InputValidationError(Exception):
    """Raised when input validation fails."""
    pass


class PathTraversalError(InputValidationError):
    """Raised when path traversal is detected."""
    pass


class InjectionError(InputValidationError):
    """Raised when injection attempt is detected."""
    pass


class LengthLimitError(InputValidationError):
    """Raised when input exceeds length limit."""
    pass


# ── Path Validation ───────────────────────────────────────────────

def validate_path(
    path: str,
    base_path: Optional[str] = None,
    allow_traversal: bool = False
) -> str:
    """
    Validate and normalize a file path.
    
    Args:
        path: Path to validate
        base_path: Base path for relative path resolution
        allow_traversal: Whether to allow path traversal
    
    Returns:
        Normalized path
    
    Raises:
        PathTraversalError: If path traversal is detected
        InputValidationError: If path is invalid
    """
    if not path:
        raise InputValidationError("Path cannot be empty")
    
    # Normalize path
    normalized = path.replace("\\", "/")
    normalized = re.sub(r"/+", "/", normalized)
    
    # Check for path traversal
    if not allow_traversal:
        if ".." in normalized.split("/"):
            raise PathTraversalError(f"Path traversal detected: {path}")
        
        # Check for absolute paths
        if normalized.startswith("/"):
            raise InputValidationError(f"Absolute path not allowed: {path}")
    
    # Resolve path if base_path is provided
    if base_path:
        resolved = Path(base_path) / normalized
        try:
            resolved = resolved.resolve()
        except Exception as e:
            raise InputValidationError(f"Invalid path: {e}")
        
        # Ensure resolved path is within base_path
        base_resolved = Path(base_path).resolve()
        if not str(resolved).startswith(str(base_resolved)):
            raise PathTraversalError(f"Path escapes base directory: {path}")
        
        return str(resolved)
    
    return normalized


def sanitize_path(path: str) -> str:
    """
    Sanitize a path by removing dangerous characters.
    
    Args:
        path: Path to sanitize
    
    Returns:
        Sanitized path
    """
    # Remove null bytes
    path = path.replace("\x00", "")
    
    # Remove control characters
    path = re.sub(r"[\x00-\x1f\x7f]", "", path)
    
    # Normalize path separators
    path = path.replace("\\", "/")
    
    # Remove duplicate slashes
    path = re.sub(r"/+", "/", path)
    
    # Remove leading/trailing whitespace
    path = path.strip()
    
    return path


# ── String Validation ─────────────────────────────────────────────

def validate_string(
    value: str,
    max_length: int = 1000,
    min_length: int = 0,
    pattern: Optional[str] = None,
    name: str = "input"
) -> str:
    """
    Validate a string input.
    
    Args:
        value: String to validate
        max_length: Maximum allowed length
        min_length: Minimum required length
        pattern: Regex pattern to match
        name: Name for error messages
    
    Returns:
        Validated string
    
    Raises:
        InputValidationError: If validation fails
    """
    if not isinstance(value, str):
        raise InputValidationError(f"{name} must be a string")
    
    if len(value) < min_length:
        raise LengthLimitError(f"{name} too short: {len(value)} < {min_length}")
    
    if len(value) > max_length:
        raise LengthLimitError(f"{name} too long: {len(value)} > {max_length}")
    
    if pattern and not re.match(pattern, value):
        raise InputValidationError(f"{name} does not match required pattern")
    
    return value


def sanitize_string(value: str, max_length: int = 1000) -> str:
    """
    Sanitize a string input.
    
    Args:
        value: String to sanitize
        max_length: Maximum allowed length
    
    Returns:
        Sanitized string
    """
    if not isinstance(value, str):
        return ""
    
    # Remove control characters
    value = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", value)
    
    # Trim to max length
    value = value[:max_length]
    
    # Strip whitespace
    value = value.strip()
    
    return value


# ── Injection Prevention ──────────────────────────────────────────

# Dangerous patterns for injection attacks
INJECTION_PATTERNS = [
    # Script injection
    r"<script[^>]*>",
    r"javascript:",
    r"vbscript:",
    r"data:",
    
    # Command injection
    r"\$\(",
    r"`[^`]*`",
    r"\|\s*bash",
    r"\|\s*sh",
    
    # Path traversal
    r"\.\./",
    r"\.\.\\",
    r"%2e%2e",
    
    # SQL injection (basic patterns)
    r"'\s*or\s+1\s*=\s*1",
    r";\s*drop\s+table",
    r"--\s*$",
    
    # LDAP injection
    r"\*\)\(\|",
    r"\)\(\|",
]


def check_injection(value: str, name: str = "input") -> None:
    """
    Check for injection attempts in a string.
    
    Args:
        value: String to check
        name: Name for error messages
    
    Raises:
        InjectionError: If injection attempt is detected
    """
    if not isinstance(value, str):
        return
    
    value_lower = value.lower()
    
    for pattern in INJECTION_PATTERNS:
        if re.search(pattern, value_lower, re.IGNORECASE):
            raise InjectionError(f"Potential injection detected in {name}: {pattern}")


def sanitize_for_display(value: str) -> str:
    """
    Sanitize a string for safe display.
    
    Args:
        value: String to sanitize
    
    Returns:
        Sanitized string safe for display
    """
    if not isinstance(value, str):
        return ""
    
    # HTML entity encoding
    value = value.replace("&", "&amp;")
    value = value.replace("<", "&lt;")
    value = value.replace(">", "&gt;")
    value = value.replace('"', "&quot;")
    value = value.replace("'", "&#x27;")
    
    return value


# ── Numeric Validation ────────────────────────────────────────────

def validate_numeric(
    value: any,
    min_value: Optional[float] = None,
    max_value: Optional[float] = None,
    name: str = "value"
) -> float:
    """
    Validate a numeric input.
    
    Args:
        value: Value to validate
        min_value: Minimum allowed value
        max_value: Maximum allowed value
        name: Name for error messages
    
    Returns:
        Validated numeric value
    
    Raises:
        InputValidationError: If validation fails
    """
    try:
        num = float(value)
    except (TypeError, ValueError):
        raise InputValidationError(f"{name} must be a number")
    
    if min_value is not None and num < min_value:
        raise InputValidationError(f"{name} too small: {num} < {min_value}")
    
    if max_value is not None and num > max_value:
        raise InputValidationError(f"{name} too large: {num} > {max_value}")
    
    return num


# ── Image Validation ──────────────────────────────────────────────

def validate_image(
    image_data: bytes,
    max_size: int = 20 * 1024 * 1024,  # 20 MB
    allowed_formats: Optional[set] = None
) -> Tuple[bool, Optional[str]]:
    """
    Validate image data.
    
    Args:
        image_data: Image bytes
        max_size: Maximum allowed size
        allowed_formats: Set of allowed formats
    
    Returns:
        (is_valid, error_message)
    """
    if allowed_formats is None:
        allowed_formats = {"PNG", "JPEG", "JPG", "WEBP"}
    
    # Check size
    if len(image_data) > max_size:
        return False, f"Image too large: {len(image_data)} bytes"
    
    # Check format using magic bytes
    try:
        from PIL import Image
        import io
        
        img = Image.open(io.BytesIO(image_data))
        fmt = img.format
        
        if fmt not in allowed_formats:
            return False, f"Unsupported image format: {fmt}"
        
        # Verify image integrity
        img.verify()
        
    except ImportError:
        # PIL not available, skip format validation
        pass
    except Exception as e:
        return False, f"Invalid image: {e}"
    
    return True, None


# ── JSON Validation ───────────────────────────────────────────────

def validate_json(
    data: dict,
    required_fields: Optional[list] = None,
    optional_fields: Optional[list] = None,
    max_depth: int = 10
) -> dict:
    """
    Validate JSON/dict input.
    
    Args:
        data: Dictionary to validate
        required_fields: List of required field names
        optional_fields: List of optional field names
        max_depth: Maximum nesting depth
    
    Returns:
        Validated dictionary
    
    Raises:
        InputValidationError: If validation fails
    """
    if not isinstance(data, dict):
        raise InputValidationError("Input must be a dictionary")
    
    # Check nesting depth
    def check_depth(obj, current_depth=0):
        if current_depth > max_depth:
            raise InputValidationError(f"JSON nesting too deep: > {max_depth}")
        if isinstance(obj, dict):
            for v in obj.values():
                check_depth(v, current_depth + 1)
        elif isinstance(obj, list):
            for v in obj:
                check_depth(v, current_depth + 1)
    
    check_depth(data)
    
    # Check required fields
    if required_fields:
        for field in required_fields:
            if field not in data:
                raise InputValidationError(f"Missing required field: {field}")
    
    return data


# ── Common Validation Functions ───────────────────────────────────

def validate_task_description(description: str) -> str:
    """
    Validate a task description.
    
    Args:
        description: Task description
    
    Returns:
        Validated description
    
    Raises:
        InputValidationError: If validation fails
    """
    description = validate_string(description, max_length=1000, name="task description")
    check_injection(description, name="task description")
    return sanitize_string(description)


def validate_repo_path(path: str) -> str:
    """
    Validate a repository path.
    
    Args:
        path: Repository path
    
    Returns:
        Validated path
    
    Raises:
        InputValidationError: If validation fails
    """
    path = validate_path(path, allow_traversal=False)
    return sanitize_path(path)


def validate_api_key(key: str) -> str:
    """
    Validate an API key.
    
    Args:
        key: API key
    
    Returns:
        Validated key
    
    Raises:
        InputValidationError: If validation fails
    """
    if not key:
        raise InputValidationError("API key cannot be empty")
    
    # Basic format check (alphanumeric and common separators)
    if not re.match(r"^[a-zA-Z0-9\-_\.]+$", key):
        raise InputValidationError("Invalid API key format")
    
    return key
