#!/usr/bin/env python3
"""
Oracle OS Vision Sidecar — HTTP server for VLM grounding and element detection.

Runs on localhost:9876. Oracle OS v2 (Swift) calls this when the AX tree
can't find what the agent needs (web apps, dynamic content, etc.).

Architecture:
  Layer 1: YOLO element detection (<200ms) — finds ALL interactive elements
  Layer 2: VLM precision grounding (0.5-3s) — finds ONE specific element

Endpoints:
  GET  /health    — Check if models are loaded and server is ready
  POST /ground    — Find precise coordinates for a described element
  POST /detect    — Experimental placeholder for full-screen detection
  POST /parse     — Experimental placeholder for structured screen parsing

Security:
  - Binds to localhost (127.0.0.1) only by default
  - Rate limiting: 10 requests/second per client IP
  - Input validation: image format, size limits, required fields
  - Security headers: X-Content-Type-Options, X-Frame-Options
  - No sensitive data in error responses

The server uses Python's built-in http.server to minimize dependencies.
Models are loaded lazily on first request and kept warm in memory.

Usage:
  python3 server.py                           # Default: port 9876, auto-detect model
  python3 server.py --port 9877               # Custom port
  python3 server.py --model-path /path/to/model  # Explicit model path
  python3 server.py --idle-timeout 600        # Auto-exit after 10 min idle (default)
  python3 server.py --health-check            # Test model loading, then exit
  python3 server.py --version                 # Print version
"""

__version__ = "2.2.0"

import argparse
import base64
import hashlib
import io
import json
import os
import re
import signal
import sys
import tempfile
import time
import traceback
import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from threading import Lock, Timer
from typing import Optional

# ── Configuration ──────────────────────────────────────────────────

# These are set by parse_args() before anything else runs
HOST = "127.0.0.1"
PORT = 9876
MODEL_PATH = ""
IDLE_TIMEOUT = 600  # seconds (0 = no timeout)

# Security: Rate limiting configuration
RATE_LIMIT_REQUESTS = 10  # Max requests per window
RATE_LIMIT_WINDOW = 1.0   # Window size in seconds
MAX_BODY_SIZE = 50 * 1024 * 1024  # 50 MB
MAX_IMAGE_SIZE = 20 * 1024 * 1024  # 20 MB for images
ALLOWED_IMAGE_FORMATS = {"PNG", "JPEG", "JPG", "WEBP"}

# Caching configuration
CACHE_ENABLED = True
CACHE_MAX_SIZE = 100  # Max cached entries
CACHE_TTL = 300  # Cache TTL in seconds (5 minutes)

# ── Metrics Tracking ──────────────────────────────────────────────

@dataclass
class Metrics:
    """Thread-safe metrics collector for Prometheus-style monitoring."""
    _lock: Lock = field(default_factory=Lock, repr=False)
    _start_time: float = field(default_factory=time.time, repr=False)
    
    # Request counters
    total_requests: int = 0
    requests_by_endpoint: dict = field(default_factory=lambda: defaultdict(int))
    requests_by_status: dict = field(default_factory=lambda: defaultdict(int))
    error_count: int = 0
    
    # Timing metrics
    ground_count: int = 0
    ground_total_ms: float = 0
    ground_min_ms: float = float('inf')
    ground_max_ms: float = 0
    
    detect_count: int = 0
    detect_total_ms: float = 0
    
    parse_count: int = 0
    parse_total_ms: float = 0
    
    # Cache metrics
    cache_hits: int = 0
    cache_misses: int = 0
    
    # Rate limit metrics
    rate_limit_rejections: int = 0
    
    # Model metrics
    model_load_count: int = 0
    model_load_errors: int = 0
    
    def record_request(self, endpoint: str, status: int, duration_ms: float = 0):
        """Record a completed request."""
        with self._lock:
            self.total_requests += 1
            self.requests_by_endpoint[endpoint] += 1
            self.requests_by_status[str(status)] += 1
            
            if status >= 400:
                self.error_count += 1
    
    def record_ground(self, duration_ms: float):
        """Record a grounding request."""
        with self._lock:
            self.ground_count += 1
            self.ground_total_ms += duration_ms
            self.ground_min_ms = min(self.ground_min_ms, duration_ms)
            self.ground_max_ms = max(self.ground_max_ms, duration_ms)
    
    def record_detect(self, duration_ms: float):
        """Record a detection request."""
        with self._lock:
            self.detect_count += 1
            self.detect_total_ms += duration_ms
    
    def record_parse(self, duration_ms: float):
        """Record a parse request."""
        with self._lock:
            self.parse_count += 1
            self.parse_total_ms += duration_ms
    
    def record_cache_hit(self):
        """Record a cache hit."""
        with self._lock:
            self.cache_hits += 1
    
    def record_cache_miss(self):
        """Record a cache miss."""
        with self._lock:
            self.cache_misses += 1
    
    def record_rate_limit_rejection(self):
        """Record a rate limit rejection."""
        with self._lock:
            self.rate_limit_rejections += 1
    
    def record_model_load(self, success: bool):
        """Record a model load attempt."""
        with self._lock:
            self.model_load_count += 1
            if not success:
                self.model_load_errors += 1
    
    def to_dict(self) -> dict:
        """Export metrics as dictionary."""
        with self._lock:
            uptime = time.time() - self._start_time
            avg_ground_ms = (self.ground_total_ms / self.ground_count) if self.ground_count > 0 else 0
            avg_detect_ms = (self.detect_total_ms / self.detect_count) if self.detect_count > 0 else 0
            avg_parse_ms = (self.parse_total_ms / self.parse_count) if self.parse_count > 0 else 0
            cache_total = self.cache_hits + self.cache_misses
            cache_hit_rate = (self.cache_hits / cache_total) if cache_total > 0 else 0
            
            return {
                "uptime_seconds": round(uptime, 1),
                "total_requests": self.total_requests,
                "requests_by_endpoint": dict(self.requests_by_endpoint),
                "requests_by_status": dict(self.requests_by_status),
                "error_count": self.error_count,
                "grounding": {
                    "count": self.ground_count,
                    "avg_ms": round(avg_ground_ms, 1),
                    "min_ms": round(self.ground_min_ms, 1) if self.ground_count > 0 else 0,
                    "max_ms": round(self.ground_max_ms, 1),
                },
                "detection": {
                    "count": self.detect_count,
                    "avg_ms": round(avg_detect_ms, 1),
                },
                "parsing": {
                    "count": self.parse_count,
                    "avg_ms": round(avg_parse_ms, 1),
                },
                "cache": {
                    "hits": self.cache_hits,
                    "misses": self.cache_misses,
                    "hit_rate": round(cache_hit_rate, 3),
                },
                "rate_limit_rejections": self.rate_limit_rejections,
                "model_loads": self.model_load_count,
                "model_load_errors": self.model_load_errors,
            }
    
    def to_prometheus(self) -> str:
        """Export metrics in Prometheus exposition format."""
        with self._lock:
            lines = []
            lines.append("# HELP oracle_vision_uptime_seconds Server uptime in seconds")
            lines.append("# TYPE oracle_vision_uptime_seconds gauge")
            lines.append(f"oracle_vision_uptime_seconds {time.time() - self._start_time:.1f}")
            
            lines.append("# HELP oracle_vision_requests_total Total number of requests")
            lines.append("# TYPE oracle_vision_requests_total counter")
            lines.append(f"oracle_vision_requests_total {self.total_requests}")
            
            lines.append("# HELP oracle_vision_errors_total Total number of errors")
            lines.append("# TYPE oracle_vision_errors_total counter")
            lines.append(f"oracle_vision_errors_total {self.error_count}")
            
            lines.append("# HELP oracle_vision_ground_count Total grounding requests")
            lines.append("# TYPE oracle_vision_ground_count counter")
            lines.append(f"oracle_vision_ground_count {self.ground_count}")
            
            lines.append("# HELP oracle_vision_ground_avg_ms Average grounding latency")
            lines.append("# TYPE oracle_vision_ground_avg_ms gauge")
            avg = (self.ground_total_ms / self.ground_count) if self.ground_count > 0 else 0
            lines.append(f"oracle_vision_ground_avg_ms {avg:.1f}")
            
            lines.append("# HELP oracle_vision_cache_hit_rate Cache hit rate")
            lines.append("# TYPE oracle_vision_cache_hit_rate gauge")
            cache_total = self.cache_hits + self.cache_misses
            rate = (self.cache_hits / cache_total) if cache_total > 0 else 0
            lines.append(f"oracle_vision_cache_hit_rate {rate:.3f}")
            
            return "\n".join(lines) + "\n"


_metrics = Metrics()


# ── Request Cache ─────────────────────────────────────────────────

@dataclass
class CacheEntry:
    """A cached grounding result."""
    result: dict
    timestamp: float
    description: str
    image_hash: str


class GroundingCache:
    """LRU cache for grounding results based on image hash + description."""
    
    def __init__(self, max_size: int = CACHE_MAX_SIZE, ttl: int = CACHE_TTL):
        self.max_size = max_size
        self.ttl = ttl
        self._cache: dict[str, CacheEntry] = {}
        self._lock = Lock()
    
    def _make_key(self, image_hash: str, description: str) -> str:
        """Create cache key from image hash and description."""
        return f"{image_hash}:{description.lower().strip()}"
    
    def _image_hash(self, image_b64: str) -> str:
        """Compute fast hash of base64 image (first 1KB for speed)."""
        return hashlib.md5(image_b64[:1024].encode()).hexdigest()
    
    def get(self, image_b64: str, description: str) -> Optional[dict]:
        """Get cached result if available and fresh."""
        if not CACHE_ENABLED:
            return None
        
        key = self._make_key(self._image_hash(image_b64), description)
        
        with self._lock:
            entry = self._cache.get(key)
            if entry is None:
                return None
            
            # Check TTL
            if time.time() - entry.timestamp > self.ttl:
                del self._cache[key]
                return None
            
            return entry.result
    
    def put(self, image_b64: str, description: str, result: dict):
        """Cache a grounding result."""
        if not CACHE_ENABLED:
            return
        
        key = self._make_key(self._image_hash(image_b64), description)
        
        with self._lock:
            # Evict oldest if at capacity
            if len(self._cache) >= self.max_size and key not in self._cache:
                oldest_key = min(self._cache, key=lambda k: self._cache[k].timestamp)
                del self._cache[oldest_key]
            
            self._cache[key] = CacheEntry(
                result=result,
                timestamp=time.time(),
                description=description,
                image_hash=self._image_hash(image_b64),
            )
    
    def clear(self):
        """Clear all cached entries."""
        with self._lock:
            self._cache.clear()
    
    def stats(self) -> dict:
        """Get cache statistics."""
        with self._lock:
            return {
                "size": len(self._cache),
                "max_size": self.max_size,
                "ttl": self.ttl,
                "enabled": CACHE_ENABLED,
            }


_grounding_cache = GroundingCache()


# ── Audit Logger ──────────────────────────────────────────────────

class AuditLogger:
    """Structured audit logger for security events."""
    
    def __init__(self):
        self._lock = Lock()
        self._events: list[dict] = []
        self._max_events = 1000
    
    def log(self, event_type: str, details: dict, severity: str = "info"):
        """Log a security event."""
        event = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "event_type": event_type,
            "severity": severity,
            "details": details,
        }
        
        with self._lock:
            self._events.append(event)
            # Trim old events
            if len(self._events) > self._max_events:
                self._events = self._events[-self._max_events:]
        
        # Also log to stderr
        log(f"[AUDIT] {event_type}: {json.dumps(details)}")
    
    def get_events(self, limit: int = 100) -> list[dict]:
        """Get recent audit events."""
        with self._lock:
            return self._events[-limit:]


_audit = AuditLogger()

# ── Model Path Resolution ─────────────────────────────────────────

def resolve_model_path(explicit_path=None):
    """
    Find the ShowUI-2B model in order of priority:
      1. Explicit --model-path argument
      2. /opt/homebrew/share/oracle-os/models/ShowUI-2B/ (Homebrew install)
      3. ~/.oracle-os/models/ShowUI-2B/ (user-local install)
      4. ~/.shadow/models/llm/ShowUI-2B-bf16-8bit/ (legacy Shadow path)

    Returns the first path that exists and contains model.safetensors,
    or the first candidate path (for error messages) if none found.
    """
    candidates = []

    if explicit_path:
        candidates.append(explicit_path)

    candidates.extend([
        "/opt/homebrew/share/oracle-os/models/ShowUI-2B",
        str(Path.home() / ".oracle-os/models/ShowUI-2B"),
        str(Path.home() / ".shadow/models/llm/ShowUI-2B-bf16-8bit"),
    ])

    for path in candidates:
        if os.path.isdir(path):
            # Verify it looks like a real model directory
            safetensors = os.path.join(path, "model.safetensors")
            config = os.path.join(path, "config.json")
            if os.path.isfile(safetensors) and os.path.isfile(config):
                return path

    # Return first candidate for error message
    return candidates[0] if candidates else str(Path.home() / ".oracle-os/models/ShowUI-2B")


# ── Model State (lazy-loaded, thread-safe) ─────────────────────────

_vlm_model = None
_vlm_processor = None
_vlm_tokenizer = None
_vlm_lock = Lock()
_vlm_load_error = None


# ── Rate Limiter ──────────────────────────────────────────────────

class RateLimiter:
    """Token bucket rate limiter for request throttling."""

    def __init__(self, max_requests: int = RATE_LIMIT_REQUESTS, window: float = RATE_LIMIT_WINDOW):
        self.max_requests = max_requests
        self.window = window
        self._requests: dict[str, list[float]] = defaultdict(list)
        self._lock = Lock()

    def is_allowed(self, client_ip: str) -> bool:
        """Check if request from client_ip is allowed."""
        now = time.time()
        with self._lock:
            # Clean old requests outside window
            self._requests[client_ip] = [
                t for t in self._requests[client_ip] if now - t < self.window
            ]
            # Check if under limit
            if len(self._requests[client_ip]) < self.max_requests:
                self._requests[client_ip].append(now)
                return True
            return False

    def get_remaining(self, client_ip: str) -> int:
        """Get remaining requests in current window."""
        now = time.time()
        with self._lock:
            self._requests[client_ip] = [
                t for t in self._requests[client_ip] if now - t < self.window
            ]
            return max(0, self.max_requests - len(self._requests[client_ip]))


_rate_limiter = RateLimiter()


# ── Input Validation ──────────────────────────────────────────────

def validate_image_input(image_b64: str, max_size: int = MAX_IMAGE_SIZE) -> tuple[bool, str | None]:
    """
    Validate base64 encoded image input.
    
    Returns:
        (is_valid, error_message)
    """
    if not image_b64:
        return False, "Missing image data"
    
    # Check base64 size (approximate: decoded size ~ 4/3 of encoded)
    encoded_size = len(image_b64)
    if encoded_size > max_size * 1.5:  # Allow some overhead for base64 encoding
        return False, f"Image too large: {encoded_size} bytes (max: {int(max_size * 1.5)})"
    
    try:
        image_data = base64.b64decode(image_b64, validate=True)
    except Exception:
        return False, "Invalid base64 encoding"
    
    # Check decoded size
    if len(image_data) > max_size:
        return False, f"Image too large: {len(image_data)} bytes (max: {max_size})"
    
    # Try to open with PIL to validate format
    try:
        from PIL import Image
        img = Image.open(io.BytesIO(image_data))
        img.verify()  # Verify image integrity
    except ImportError:
        # PIL not available, skip format validation
        pass
    except Exception as e:
        return False, f"Invalid image format: {e}"
    
    return True, None


def validate_description(description: str, max_length: int = 1000) -> tuple[bool, str | None]:
    """
    Validate description input.
    
    Returns:
        (is_valid, error_message)
    """
    if not description or not description.strip():
        return False, "Missing or empty description"
    
    if len(description) > max_length:
        return False, f"Description too long: {len(description)} chars (max: {max_length})"
    
    # Check for potentially malicious content
    dangerous_patterns = [
        r'<script', r'javascript:', r'data:', r'file://',
        r'\.\.\/', r'\.\.\\',  # Path traversal
    ]
    for pattern in dangerous_patterns:
        if re.search(pattern, description, re.IGNORECASE):
            return False, "Description contains potentially dangerous content"
    
    return True, None


def validate_screen_dimensions(screen_w: float, screen_h: float) -> tuple[bool, str | None]:
    """
    Validate screen dimensions.
    
    Returns:
        (is_valid, error_message)
    """
    if screen_w <= 0 or screen_w > 10000:
        return False, f"Invalid screen_w: {screen_w} (must be 1-10000)"
    if screen_h <= 0 or screen_h > 10000:
        return False, f"Invalid screen_h: {screen_h} (must be 1-10000)"
    return True, None


def validate_crop_box(crop_box: list, screen_w: float, screen_h: float) -> tuple[bool, str | None]:
    """
    Validate crop_box coordinates.
    
    Returns:
        (is_valid, error_message)
    """
    if not isinstance(crop_box, list) or len(crop_box) != 4:
        return False, "crop_box must be [x1, y1, x2, y2]"
    
    x1, y1, x2, y2 = crop_box
    if not all(isinstance(v, (int, float)) for v in crop_box):
        return False, "crop_box values must be numbers"
    
    if x1 < 0 or y1 < 0 or x2 > screen_w or y2 > screen_h:
        return False, f"crop_box out of bounds: {crop_box}"
    
    if x2 <= x1 or y2 <= y1:
        return False, "crop_box must have positive area"
    
    return True, None


def _load_vlm():
    """Load ShowUI-2B model. Called once, cached forever."""
    global _vlm_model, _vlm_processor, _vlm_tokenizer, _vlm_load_error

    with _vlm_lock:
        if _vlm_model is not None:
            return True
        if _vlm_load_error is not None:
            return False

        try:
            log(f"Loading ShowUI-2B from {MODEL_PATH}...")
            t0 = time.time()

            from mlx_vlm import load
            _vlm_model, _vlm_processor = load(MODEL_PATH)

            # CRITICAL: Force the slow image processor. The fast Qwen2VLImageProcessor
            # requires PyTorch tensors which MLX doesn't provide.
            from transformers import Qwen2VLImageProcessor
            _vlm_processor.image_processor = Qwen2VLImageProcessor.from_pretrained(
                MODEL_PATH, use_fast=False
            )

            from transformers import AutoTokenizer
            _vlm_tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)

            log(f"ShowUI-2B loaded in {time.time() - t0:.1f}s")
            _metrics.record_model_load(True)
            _audit.log("model_loaded", {"model": "ShowUI-2B", "path": MODEL_PATH})
            return True
        except Exception as e:
            _vlm_load_error = str(e)
            log(f"ERROR loading ShowUI-2B: {e}")
            traceback.print_exc(file=sys.stderr)
            _metrics.record_model_load(False)
            _audit.log("model_load_failed", {"error": str(e)}, severity="error")
            return False


def _reload_vlm():
    """Hot-reload the VLM model. Returns (success, message)."""
    global _vlm_model, _vlm_processor, _vlm_tokenizer, _vlm_load_error

    with _vlm_lock:
        log("Hot-reloading VLM model...")
        t0 = time.time()
        
        try:
            # Clear old model
            _vlm_model = None
            _vlm_processor = None
            _vlm_tokenizer = None
            _vlm_load_error = None
            
            # Reload
            from mlx_vlm import load
            _vlm_model, _vlm_processor = load(MODEL_PATH)
            
            from transformers import Qwen2VLImageProcessor
            _vlm_processor.image_processor = Qwen2VLImageProcessor.from_pretrained(
                MODEL_PATH, use_fast=False
            )
            
            from transformers import AutoTokenizer
            _vlm_tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)
            
            elapsed = time.time() - t0
            log(f"VLM model reloaded in {elapsed:.1f}s")
            _audit.log("model_reloaded", {"model": "ShowUI-2B", "elapsed_s": round(elapsed, 1)})
            return True, f"Model reloaded in {elapsed:.1f}s"
            
        except Exception as e:
            _vlm_load_error = str(e)
            log(f"ERROR reloading VLM: {e}")
            traceback.print_exc(file=sys.stderr)
            _audit.log("model_reload_failed", {"error": str(e)}, severity="error")
            return False, str(e)


def _vlm_ground(image_path: str, description: str, screen_w: float, screen_h: float) -> dict:
    """
    Run ShowUI-2B grounding on an image.

    Args:
        image_path: Path to image file (will be resized internally)
        description: What to find (e.g., "Compose button")
        screen_w: Logical width in points (used to scale normalized output)
        screen_h: Logical height in points

    Returns:
        {"x": float, "y": float, "confidence": float, "raw": str}
    """
    from PIL import Image
    from typing import Any
    # Resize to ~1280px max edge for ShowUI-2B's pixel budget
    img: Any = Image.open(image_path)
    max_edge = 1280
    w, h = img.size
    _f = tempfile.NamedTemporaryFile(suffix=".jpg", prefix="oracle_vlm_", delete=False)
    resized_path = _f.name
    _f.close()
    if max(w, h) > max_edge:
        scale = max_edge / max(w, h)
        resample_method = getattr(Image, "Resampling", Image).LANCZOS
        img = img.resize((int(w * scale), int(h * scale)), resample_method)
    img.convert("RGB").save(resized_path, format="JPEG", quality=85)

    # ShowUI-2B prompt format
    system_text = (
        "Based on the screenshot of the page, I give a text description and you give its "
        "corresponding location. The coordinate represents a clickable location [x, y] for "
        "an element, which is a relative coordinate on the screenshot, scaled from 0 to 1."
    )
    prompt = f"{system_text}\n{description}"

    from mlx_vlm import stream_generate

    # Build chat template
    chat = [{"role": "user", "content": [
        {"type": "image", "image": resized_path},
        {"type": "text", "text": prompt}
    ]}]
    if _vlm_tokenizer is not None and hasattr(_vlm_tokenizer, "apply_chat_template"):
        formatted = _vlm_tokenizer.apply_chat_template(
            chat, tokenize=False, add_generation_prompt=True
        )
    else:
        formatted = prompt

    # Run inference
    t0 = time.time()
    full_text = ""
    for result in stream_generate(
        _vlm_model, _vlm_processor, formatted,
        image=resized_path,
        max_tokens=128,
        temp=0.0
    ):
        full_text += result.text if hasattr(result, 'text') else str(result)

    elapsed = time.time() - t0
    log(f"VLM '{description}' -> '{full_text.strip()}' ({elapsed:.1f}s)")

    # Clean up temp file
    try:
        os.unlink(resized_path)
    except OSError:
        pass

    # Parse [x, y] or (x, y) coordinates from model output
    match = re.search(r'[\(\[]\s*([\d.]+)\s*,\s*([\d.]+)\s*[\)\]]', full_text)
    if match:
        nx, ny = float(match.group(1)), float(match.group(2))
        if nx <= 1.0 and ny <= 1.0:
            return {
                "x": round(nx * screen_w, 1),
                "y": round(ny * screen_h, 1),
                "normalized_x": round(nx, 4),
                "normalized_y": round(ny, 4),
                "confidence": 0.8,
                "raw": full_text.strip(),
                "inference_ms": int(elapsed * 1000),
            }
        else:
            # Model returned pixel coordinates instead of normalized
            return {
                "x": round(nx, 1),
                "y": round(ny, 1),
                "normalized_x": round(nx / screen_w, 4),
                "normalized_y": round(ny / screen_h, 4),
                "confidence": 0.6,
                "raw": full_text.strip(),
                "inference_ms": int(elapsed * 1000),
            }

    # Failed to parse coordinates
    return {
        "x": round(screen_w / 2, 1),
        "y": round(screen_h / 2, 1),
        "normalized_x": 0.5,
        "normalized_y": 0.5,
        "confidence": 0.0,
        "raw": full_text.strip(),
        "inference_ms": int(elapsed * 1000),
        "error": "Failed to parse coordinates from model output",
    }


# ── Idle Timeout ──────────────────────────────────────────────────

_idle_timer = None
_idle_lock = Lock()


def _reset_idle_timer():
    """Reset the idle timeout. Called on every request."""
    global _idle_timer
    if IDLE_TIMEOUT <= 0:
        return

    with _idle_lock:
        if _idle_timer is not None:
            _idle_timer.cancel()
        _idle_timer = Timer(IDLE_TIMEOUT, _idle_shutdown)
        _idle_timer.daemon = True
        _idle_timer.start()


def _idle_shutdown():
    """Called when idle timeout expires. Gracefully exits."""
    log(f"Idle timeout ({IDLE_TIMEOUT}s) reached. Shutting down.")
    # Send SIGTERM to ourselves for clean shutdown
    os.kill(os.getpid(), signal.SIGTERM)


# ── HTTP Request Handler ───────────────────────────────────────────

class VisionHandler(BaseHTTPRequestHandler):
    """Handles HTTP requests for the vision sidecar with security hardening."""

    MAX_BODY_SIZE = MAX_BODY_SIZE  # 50 MB

    def do_GET(self):
        _reset_idle_timer()
        
        # Generate request ID for tracking
        request_id = str(uuid.uuid4())[:8]
        client_ip = self.client_address[0]
        
        if self.path == "/health":
            self._handle_health(request_id)
        elif self.path == "/metrics":
            self._handle_metrics(request_id)
        elif self.path == "/config":
            self._handle_config(request_id)
        elif self.path == "/audit":
            self._handle_audit(request_id)
        elif self.path == "/cache":
            self._handle_cache_stats(request_id)
        else:
            _metrics.record_request("unknown", 404)
            self._send_json(404, {"error": "Not found", "request_id": request_id})

    def do_POST(self):
        _reset_idle_timer()
        
        # Generate request ID for tracking
        request_id = str(uuid.uuid4())[:8]
        client_ip = self.client_address[0]
        
        # Rate limiting
        if not _rate_limiter.is_allowed(client_ip):
            remaining = _rate_limiter.get_remaining(client_ip)
            _metrics.record_rate_limit_rejection()
            _audit.log("rate_limit_exceeded", {
                "client_ip": client_ip,
                "request_id": request_id,
            }, severity="warning")
            self._send_json(429, {
                "error": "Rate limit exceeded",
                "retry_after": RATE_LIMIT_WINDOW,
                "remaining": remaining,
                "request_id": request_id,
            })
            return
        
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length > self.MAX_BODY_SIZE:
                _metrics.record_request("unknown", 413)
                self._send_json(413, {"error": "Request too large", "request_id": request_id})
                return
            body = self.rfile.read(content_length)
            data = json.loads(body) if body else {}
        except (json.JSONDecodeError, ValueError):
            _metrics.record_request("unknown", 400)
            self._send_json(400, {"error": "Invalid JSON", "request_id": request_id})
            return
        except Exception:
            _metrics.record_request("unknown", 400)
            self._send_json(400, {"error": "Failed to read request body", "request_id": request_id})
            return

        if self.path == "/ground":
            self._handle_ground(data, request_id)
        elif self.path == "/ground_batch":
            self._handle_ground_batch(data, request_id)
        elif self.path == "/detect":
            self._handle_detect(data, request_id)
        elif self.path == "/parse":
            self._handle_parse(data, request_id)
        elif self.path == "/diff":
            self._handle_diff(data, request_id)
        elif self.path == "/reload":
            self._handle_reload(request_id)
        else:
            _metrics.record_request("unknown", 404)
            self._send_json(404, {"error": "Not found", "request_id": request_id})

    def _handle_health(self, request_id: str):
        models = []
        if _vlm_model is not None:
            models.append("showui-2b")

        status = "ready" if _vlm_model is not None else "idle"
        _metrics.record_request("/health", 200)
        self._send_json(200, {
            "status": status,
            "version": __version__,
            "models_loaded": models,
            "model_path": MODEL_PATH,
            "model_exists": os.path.isdir(MODEL_PATH),
            "vlm_load_error": _vlm_load_error,
            "idle_timeout": IDLE_TIMEOUT,
            "pid": os.getpid(),
            "request_id": request_id,
            "cache_enabled": CACHE_ENABLED,
            "features": [
                "ground", "ground_batch", "detect", "parse", 
                "diff", "reload", "metrics", "config", "audit",
            ],
        })

    def _handle_metrics(self, request_id: str):
        """Export metrics in JSON or Prometheus format."""
        accept = self.headers.get("Accept", "application/json")
        if "text/plain" in accept or "prometheus" in accept:
            response = _metrics.to_prometheus().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(response)))
            self.send_header("X-Request-ID", request_id)
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(response)
        else:
            _metrics.record_request("/metrics", 200)
            self._send_json(200, {
                "metrics": _metrics.to_dict(),
                "request_id": request_id,
            })

    def _handle_config(self, request_id: str):
        """Return current server configuration (non-sensitive)."""
        _metrics.record_request("/config", 200)
        self._send_json(200, {
            "version": __version__,
            "host": HOST,
            "port": PORT,
            "idle_timeout": IDLE_TIMEOUT,
            "rate_limit": {
                "max_requests": RATE_LIMIT_REQUESTS,
                "window": RATE_LIMIT_WINDOW,
            },
            "cache": _grounding_cache.stats(),
            "model_path": MODEL_PATH,
            "request_id": request_id,
        })

    def _handle_audit(self, request_id: str):
        """Return recent audit events."""
        limit = 100
        if "?" in self.path:
            from urllib.parse import parse_qs
            params = parse_qs(self.path.split("?", 1)[1])
            limit = int(params.get("limit", ["100"])[0])
        
        _metrics.record_request("/audit", 200)
        self._send_json(200, {
            "events": _audit.get_events(limit),
            "request_id": request_id,
        })

    def _handle_cache_stats(self, request_id: str):
        """Return cache statistics."""
        _metrics.record_request("/cache", 200)
        self._send_json(200, {
            "stats": _grounding_cache.stats(),
            "request_id": request_id,
        })

    def _handle_ground(self, data: dict, request_id: str):
        """
        Find precise coordinates for a described UI element.

        Required: image (base64 PNG), description (str)
        Optional: screen_w, screen_h, crop_box [x1,y1,x2,y2] in logical points
        """
        t0 = time.time()
        image_b64 = data.get("image")
        description = data.get("description")
        screen_w = float(data.get("screen_w", 1728))
        screen_h = float(data.get("screen_h", 1117))
        crop_box = data.get("crop_box")  # [x1, y1, x2, y2] logical points

        # Validate required fields
        if not image_b64:
            _metrics.record_request("/ground", 400)
            self._send_json(400, {"error": "Missing required field: image", "request_id": request_id})
            return
        if not description:
            _metrics.record_request("/ground", 400)
            self._send_json(400, {"error": "Missing required field: description", "request_id": request_id})
            return

        # Validate image input
        img_valid, img_error = validate_image_input(image_b64)
        if not img_valid:
            _metrics.record_request("/ground", 400)
            self._send_json(400, {"error": f"Invalid image: {img_error}", "request_id": request_id})
            return

        # Validate description
        desc_valid, desc_error = validate_description(description)
        if not desc_valid:
            _metrics.record_request("/ground", 400)
            self._send_json(400, {"error": f"Invalid description: {desc_error}", "request_id": request_id})
            return

        # Validate screen dimensions
        dim_valid, dim_error = validate_screen_dimensions(screen_w, screen_h)
        if not dim_valid:
            _metrics.record_request("/ground", 400)
            self._send_json(400, {"error": f"Invalid dimensions: {dim_error}", "request_id": request_id})
            return

        # Validate crop_box if provided
        if crop_box is not None:
            crop_valid, crop_error = validate_crop_box(crop_box, screen_w, screen_h)
            if not crop_valid:
                _metrics.record_request("/ground", 400)
                self._send_json(400, {"error": f"Invalid crop_box: {crop_error}", "request_id": request_id})
                return

        # Check cache
        cached = _grounding_cache.get(image_b64, description)
        if cached:
            _metrics.record_cache_hit()
            cached["cached"] = True
            cached["request_id"] = request_id
            _metrics.record_request("/ground", 200)
            self._send_json(200, cached)
            return
        
        _metrics.record_cache_miss()

        # Load model if needed
        if not _load_vlm():
            _metrics.record_request("/ground", 503)
            self._send_json(503, {
                "error": "Model not available",
                "suggestion": "Check model configuration",
                "request_id": request_id,
            })
            return

        try:
            from PIL import Image

            # Decode base64 image to temp file
            image_data = base64.b64decode(image_b64)
            img = Image.open(io.BytesIO(image_data))

            if crop_box:
                # Crop-based grounding: crop the specified region, run VLM on crop,
                # then map coordinates back to full screen.
                x1, y1, x2, y2 = crop_box
                crop_w = x2 - x1
                crop_h = y2 - y1

                # Calculate pixel coordinates for cropping
                img_w, img_h = img.size
                scale_x = img_w / screen_w
                scale_y = img_h / screen_h

                px1 = int(x1 * scale_x)
                py1 = int(y1 * scale_y)
                px2 = int(x2 * scale_x)
                py2 = int(y2 * scale_y)

                crop = img.crop((px1, py1, px2, py2))

                # Save crop to temp file
                _cf = tempfile.NamedTemporaryFile(suffix=".png", prefix="oracle_crop_", delete=False)
                crop_path = _cf.name
                _cf.close()
                crop.save(crop_path)

                # Run VLM on crop with crop dimensions
                result = _vlm_ground(crop_path, description, crop_w, crop_h)

                # Map coordinates back to full screen
                result["x"] = round(x1 + result["x"], 1)
                result["y"] = round(y1 + result["y"], 1)
                result["normalized_x"] = round(result["x"] / screen_w, 4)
                result["normalized_y"] = round(result["y"] / screen_h, 4)
                result["method"] = "crop-based"

                try:
                    os.unlink(crop_path)
                except OSError:
                    pass
            else:
                # Full-screen grounding
                _ff = tempfile.NamedTemporaryFile(suffix=".png", prefix="oracle_full_", delete=False)
                img_path = _ff.name
                _ff.close()
                img.save(img_path)

                result = _vlm_ground(img_path, description, screen_w, screen_h)
                result["method"] = "full-screen"

                try:
                    os.unlink(img_path)
                except OSError:
                    pass

            # Add metadata
            result["request_id"] = request_id
            result["cached"] = False
            
            # Cache the result
            _grounding_cache.put(image_b64, description, result)
            
            # Record metrics
            duration_ms = (time.time() - t0) * 1000
            _metrics.record_ground(duration_ms)
            _metrics.record_request("/ground", 200)
            
            self._send_json(200, result)

        except Exception as e:
            log(f"ERROR in /ground: {type(e).__name__}")
            _metrics.record_request("/ground", 500)
            _audit.log("ground_error", {"error": str(e), "request_id": request_id}, severity="error")
            self._send_json(500, {"error": "Internal processing error", "request_id": request_id})

    def _handle_detect(self, data: dict):
        """
        Detect all interactive UI elements on screen.
        """
        image_b64 = data.get("image")
        screen_w = float(data.get("screen_w", 1728))
        screen_h = float(data.get("screen_h", 1117))

        if not image_b64:
            self._send_json(400, {"error": "Missing required field: image"})
            return

        # Validate image input
        img_valid, img_error = validate_image_input(image_b64)
        if not img_valid:
            self._send_json(400, {"error": f"Invalid image: {img_error}"})
            return

        # Validate screen dimensions
        dim_valid, dim_error = validate_screen_dimensions(screen_w, screen_h)
        if not dim_valid:
            self._send_json(400, {"error": f"Invalid dimensions: {dim_error}"})
            return

        try:
            from PIL import Image
            from detectors.ui_detector import UIDetector
            
            image_data = base64.b64decode(image_b64)
            img = Image.open(io.BytesIO(image_data))
            
            detector = UIDetector(model_path=MODEL_PATH)
            elements = detector.detect(img, screen_w, screen_h)
            
            self._send_json(200, {
                "status": "success",
                "elements": [e.to_dict() for e in elements],
                "count": len(elements),
            })
        except Exception as e:
            log(f"ERROR in /detect: {type(e).__name__}")
            self._send_json(500, {"error": "Internal processing error"})

    def _handle_parse(self, data: dict, request_id: str):
        """
        Parse screen into structured element map.
        Combines YOLO detection + OCR or VLM context analysis.
        """
        t0 = time.time()
        image_b64 = data.get("image")
        screen_w = float(data.get("screen_w", 1728))
        screen_h = float(data.get("screen_h", 1117))

        if not image_b64:
            _metrics.record_request("/parse", 400)
            self._send_json(400, {"error": "Missing required field: image", "request_id": request_id})
            return

        # Validate image input
        img_valid, img_error = validate_image_input(image_b64)
        if not img_valid:
            _metrics.record_request("/parse", 400)
            self._send_json(400, {"error": f"Invalid image: {img_error}", "request_id": request_id})
            return

        # Validate screen dimensions
        dim_valid, dim_error = validate_screen_dimensions(screen_w, screen_h)
        if not dim_valid:
            _metrics.record_request("/parse", 400)
            self._send_json(400, {"error": f"Invalid dimensions: {dim_error}", "request_id": request_id})
            return

        try:
            from PIL import Image
            from fusion.parse_screen import ScreenParser
            
            image_data = base64.b64decode(image_b64)
            img = Image.open(io.BytesIO(image_data))
            
            parser = ScreenParser(model_path=MODEL_PATH)
            result = parser.parse(img, screen_w, screen_h)
            result["request_id"] = request_id
            
            duration_ms = (time.time() - t0) * 1000
            _metrics.record_parse(duration_ms)
            _metrics.record_request("/parse", 200)
            
            self._send_json(200, result)
        except Exception as e:
            log(f"ERROR in /parse: {type(e).__name__}")
            _metrics.record_request("/parse", 500)
            _audit.log("parse_error", {"error": str(e), "request_id": request_id}, severity="error")
            self._send_json(500, {"error": "Internal processing error", "request_id": request_id})

    def _handle_detect(self, data: dict, request_id: str):
        """
        Detect all interactive UI elements on screen using YOLO.
        """
        t0 = time.time()
        image_b64 = data.get("image")
        screen_w = float(data.get("screen_w", 1728))
        screen_h = float(data.get("screen_h", 1117))

        if not image_b64:
            _metrics.record_request("/detect", 400)
            self._send_json(400, {"error": "Missing required field: image", "request_id": request_id})
            return

        # Validate image input
        img_valid, img_error = validate_image_input(image_b64)
        if not img_valid:
            _metrics.record_request("/detect", 400)
            self._send_json(400, {"error": f"Invalid image: {img_error}", "request_id": request_id})
            return

        # Validate screen dimensions
        dim_valid, dim_error = validate_screen_dimensions(screen_w, screen_h)
        if not dim_valid:
            _metrics.record_request("/detect", 400)
            self._send_json(400, {"error": f"Invalid dimensions: {dim_error}", "request_id": request_id})
            return

        try:
            from PIL import Image
            from detectors.ui_detector import UIDetector
            
            image_data = base64.b64decode(image_b64)
            img = Image.open(io.BytesIO(image_data))
            
            detector = UIDetector(model_path=MODEL_PATH)
            elements = detector.detect(img, screen_w, screen_h)
            
            duration_ms = (time.time() - t0) * 1000
            _metrics.record_detect(duration_ms)
            _metrics.record_request("/detect", 200)
            
            self._send_json(200, {
                "status": "success",
                "elements": [e.to_dict() for e in elements],
                "count": len(elements),
                "request_id": request_id,
            })
        except Exception as e:
            log(f"ERROR in /detect: {type(e).__name__}")
            _metrics.record_request("/detect", 500)
            _audit.log("detect_error", {"error": str(e), "request_id": request_id}, severity="error")
            self._send_json(500, {"error": "Internal processing error", "request_id": request_id})

    def _handle_ground_batch(self, data: dict, request_id: str):
        """
        Batch grounding for multiple elements in a single screenshot.
        
        Required: image (base64 PNG), descriptions (list of str)
        Optional: screen_w, screen_h, crop_box
        """
        t0 = time.time()
        image_b64 = data.get("image")
        descriptions = data.get("descriptions")
        screen_w = float(data.get("screen_w", 1728))
        screen_h = float(data.get("screen_h", 1117))
        crop_box = data.get("crop_box")

        # Validate inputs
        if not image_b64:
            _metrics.record_request("/ground_batch", 400)
            self._send_json(400, {"error": "Missing required field: image", "request_id": request_id})
            return
        if not descriptions or not isinstance(descriptions, list):
            _metrics.record_request("/ground_batch", 400)
            self._send_json(400, {"error": "Missing required field: descriptions (list)", "request_id": request_id})
            return
        if len(descriptions) > 10:
            _metrics.record_request("/ground_batch", 400)
            self._send_json(400, {"error": "Too many descriptions (max 10)", "request_id": request_id})
            return

        # Validate image
        img_valid, img_error = validate_image_input(image_b64)
        if not img_valid:
            _metrics.record_request("/ground_batch", 400)
            self._send_json(400, {"error": f"Invalid image: {img_error}", "request_id": request_id})
            return

        # Validate screen dimensions
        dim_valid, dim_error = validate_screen_dimensions(screen_w, screen_h)
        if not dim_valid:
            _metrics.record_request("/ground_batch", 400)
            self._send_json(400, {"error": f"Invalid dimensions: {dim_error}", "request_id": request_id})
            return

        # Validate descriptions
        for desc in descriptions:
            desc_valid, desc_error = validate_description(desc)
            if not desc_valid:
                _metrics.record_request("/ground_batch", 400)
                self._send_json(400, {"error": f"Invalid description: {desc_error}", "request_id": request_id})
                return

        # Load model if needed
        if not _load_vlm():
            _metrics.record_request("/ground_batch", 503)
            self._send_json(503, {
                "error": "Model not available",
                "request_id": request_id,
            })
            return

        try:
            from PIL import Image
            
            image_data = base64.b64decode(image_b64)
            img = Image.open(io.BytesIO(image_data))
            
            # Save image to temp file
            _ff = tempfile.NamedTemporaryFile(suffix=".png", prefix="oracle_batch_", delete=False)
            img_path = _ff.name
            _ff.close()
            img.save(img_path)
            
            results = []
            for desc in descriptions:
                # Check cache first
                cached = _grounding_cache.get(image_b64, desc)
                if cached:
                    _metrics.record_cache_hit()
                    cached["cached"] = True
                    results.append(cached)
                    continue
                
                _metrics.record_cache_miss()
                
                # Run VLM grounding
                result = _vlm_ground(img_path, desc, screen_w, screen_h)
                result["method"] = "full-screen"
                result["description"] = desc
                
                # Cache the result
                _grounding_cache.put(image_b64, desc, result)
                results.append(result)
            
            try:
                os.unlink(img_path)
            except OSError:
                pass
            
            duration_ms = (time.time() - t0) * 1000
            _metrics.record_ground(duration_ms)
            _metrics.record_request("/ground_batch", 200)
            
            self._send_json(200, {
                "results": results,
                "count": len(results),
                "request_id": request_id,
            })
            
        except Exception as e:
            log(f"ERROR in /ground_batch: {type(e).__name__}")
            _metrics.record_request("/ground_batch", 500)
            _audit.log("ground_batch_error", {"error": str(e), "request_id": request_id}, severity="error")
            self._send_json(500, {"error": "Internal processing error", "request_id": request_id})

    def _handle_diff(self, data: dict, request_id: str):
        """
        Detect changes between two screenshots.
        
        Required: image_a (base64 PNG), image_b (base64 PNG)
        Optional: threshold (0-1, default 0.1)
        """
        t0 = time.time()
        image_a_b64 = data.get("image_a")
        image_b_b64 = data.get("image_b")
        threshold = float(data.get("threshold", 0.1))

        if not image_a_b64 or not image_b_b64:
            _metrics.record_request("/diff", 400)
            self._send_json(400, {
                "error": "Missing required fields: image_a, image_b",
                "request_id": request_id,
            })
            return

        # Validate images
        for name, img_b64 in [("image_a", image_a_b64), ("image_b", image_b_b64)]:
            img_valid, img_error = validate_image_input(img_b64)
            if not img_valid:
                _metrics.record_request("/diff", 400)
                self._send_json(400, {
                    "error": f"Invalid {name}: {img_error}",
                    "request_id": request_id,
                })
                return

        try:
            from PIL import Image
            import numpy as np
            
            # Decode images
            img_a = Image.open(io.BytesIO(base64.b64decode(image_a_b64))).convert("RGB")
            img_b = Image.open(io.BytesIO(base64.b64decode(image_b_b64))).convert("RGB")
            
            # Resize if different sizes
            if img_a.size != img_b.size:
                img_b = img_b.resize(img_a.size, Image.Resampling.LANCZOS)
            
            # Convert to numpy arrays
            arr_a = np.array(img_a, dtype=np.float32)
            arr_b = np.array(img_b, dtype=np.float32)
            
            # Calculate absolute difference
            diff = np.abs(arr_a - arr_b)
            
            # Calculate change metrics
            mean_diff = float(np.mean(diff))
            max_diff = float(np.max(diff))
            changed_pixels = int(np.sum(np.max(diff, axis=2) > threshold * 255))
            total_pixels = arr_a.shape[0] * arr_a.shape[1]
            change_ratio = changed_pixels / total_pixels if total_pixels > 0 else 0
            
            # Find bounding box of changes
            change_mask = np.max(diff, axis=2) > threshold * 255
            if np.any(change_mask):
                rows = np.any(change_mask, axis=1)
                cols = np.any(change_mask, axis=0)
                rmin, rmax = np.where(rows)[0][[0, -1]]
                cmin, cmax = np.where(cols)[0][[0, -1]]
                bbox = [int(cmin), int(rmin), int(cmax), int(rmax)]
            else:
                bbox = None
            
            duration_ms = (time.time() - t0) * 1000
            _metrics.record_request("/diff", 200)
            
            self._send_json(200, {
                "has_changes": change_ratio > 0.001,
                "change_ratio": round(change_ratio, 4),
                "changed_pixels": changed_pixels,
                "total_pixels": total_pixels,
                "mean_diff": round(mean_diff, 2),
                "max_diff": round(max_diff, 2),
                "bbox": bbox,
                "threshold": threshold,
                "inference_ms": int(duration_ms),
                "request_id": request_id,
            })
            
        except ImportError:
            _metrics.record_request("/diff", 501)
            self._send_json(501, {
                "error": "numpy required for /diff endpoint",
                "request_id": request_id,
            })
        except Exception as e:
            log(f"ERROR in /diff: {type(e).__name__}")
            _metrics.record_request("/diff", 500)
            _audit.log("diff_error", {"error": str(e), "request_id": request_id}, severity="error")
            self._send_json(500, {"error": "Internal processing error", "request_id": request_id})

    def _handle_reload(self, request_id: str):
        """
        Hot-reload the VLM model without restarting the server.
        """
        _audit.log("model_reload_requested", {"request_id": request_id})
        success, message = _reload_vlm()
        
        if success:
            _metrics.record_request("/reload", 200)
            self._send_json(200, {
                "status": "success",
                "message": message,
                "request_id": request_id,
            })
        else:
            _metrics.record_request("/reload", 500)
            self._send_json(500, {
                "status": "error",
                "message": message,
                "request_id": request_id,
            })

    def _send_json(self, status: int, data: dict):
        response = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        # Security headers
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        # Request ID header if present
        if "request_id" in data:
            self.send_header("X-Request-ID", data["request_id"])
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, format, *args):
        """Override to send access logs to stderr with our format."""
        log(f"HTTP {args[0]}")


# ── Logging ────────────────────────────────────────────────────────

def log(msg: str):
    ts = time.strftime("%Y-%m-%dT%H:%M:%S")
    print(f"[{ts}] [VISION] {msg}", file=sys.stderr, flush=True)


# ── Signal Handling ────────────────────────────────────────────────

_server_instance = None


def _signal_handler(signum, frame):
    """Handle SIGTERM and SIGINT for clean shutdown."""
    signame = signal.Signals(signum).name
    log(f"Received {signame}, shutting down...")
    if _server_instance is not None:
        # shutdown() must be called from a different thread than serve_forever()
        import threading
        threading.Thread(target=_server_instance.shutdown, daemon=True).start()
    else:
        sys.exit(0)


# ── CLI Argument Parsing ──────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(
        prog="oracle-vision",
        description="Oracle OS Vision Sidecar — VLM grounding server for UI element detection",
    )
    parser.add_argument(
        "--version", action="version", version=f"oracle-vision {__version__}",
    )
    parser.add_argument(
        "--host", default="127.0.0.1",
        help="Host to bind to (default: 127.0.0.1). Security: Only localhost binding is recommended.",
    )
    parser.add_argument(
        "--port", type=int,
        default=int(os.environ.get("ORACLE_VISION_PORT", "9876")),
        help="Port to listen on (default: 9876, or ORACLE_VISION_PORT env var)",
    )
    parser.add_argument(
        "--model-path", default=None,
        help="Path to ShowUI-2B model directory. Auto-detected if not specified.",
    )
    parser.add_argument(
        "--idle-timeout", type=int, default=600,
        help="Auto-exit after N seconds of no requests (default: 600, 0 to disable)",
    )
    parser.add_argument(
        "--preload", action="store_true",
        help="Pre-load the VLM model at startup instead of lazy-loading on first request",
    )
    parser.add_argument(
        "--health-check", action="store_true",
        help="Test that the model can load, then exit (for setup verification)",
    )
    parser.add_argument(
        "--rate-limit", type=int, default=RATE_LIMIT_REQUESTS,
        help=f"Max requests per second per client IP (default: {RATE_LIMIT_REQUESTS})",
    )
    parser.add_argument(
        "--cache", action="store_true", default=True,
        help="Enable request caching (default: enabled)",
    )
    parser.add_argument(
        "--no-cache", action="store_true",
        help="Disable request caching",
    )
    parser.add_argument(
        "--cache-ttl", type=int, default=CACHE_TTL,
        help=f"Cache TTL in seconds (default: {CACHE_TTL})",
    )
    parser.add_argument(
        "--cache-size", type=int, default=CACHE_MAX_SIZE,
        help=f"Max cache entries (default: {CACHE_MAX_SIZE})",
    )
    return parser.parse_args()


# ── Main ───────────────────────────────────────────────────────────

def main():
    global HOST, PORT, MODEL_PATH, IDLE_TIMEOUT, _server_instance, CACHE_ENABLED, CACHE_TTL, CACHE_MAX_SIZE

    args = parse_args()

    HOST = args.host
    PORT = args.port
    MODEL_PATH = resolve_model_path(args.model_path)
    IDLE_TIMEOUT = args.idle_timeout
    
    # Configure caching
    CACHE_ENABLED = not args.no_cache
    CACHE_TTL = args.cache_ttl
    CACHE_MAX_SIZE = args.cache_size
    global _grounding_cache
    _grounding_cache = GroundingCache(max_size=CACHE_MAX_SIZE, ttl=CACHE_TTL)

    # Configure rate limiter
    global _rate_limiter
    _rate_limiter = RateLimiter(max_requests=args.rate_limit)

    # Security warning if binding to non-localhost
    if HOST != "127.0.0.1" and HOST != "localhost":
        log(f"WARNING: Binding to non-localhost address {HOST}. This may expose the server to network access.")
        _audit.log("non_localhost_binding", {"host": HOST}, severity="warning")

    # --health-check: try to load model and exit
    if args.health_check:
        log(f"Health check: loading model from {MODEL_PATH}")
        if not os.path.isdir(MODEL_PATH):
            log(f"ERROR: Model directory not found")
            sys.exit(1)
        if _load_vlm():
            log("Health check passed: model loaded successfully")
            sys.exit(0)
        else:
            log(f"Health check FAILED")
            sys.exit(1)

    # Install signal handlers
    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    log(f"Oracle OS Vision Sidecar v{__version__} starting on {HOST}:{PORT}")
    log(f"Security: Rate limiting {args.rate_limit} req/s, localhost-only binding")
    log(f"Cache: {'enabled' if CACHE_ENABLED else 'disabled'} (TTL={CACHE_TTL}s, max={CACHE_MAX_SIZE})")
    if IDLE_TIMEOUT > 0:
        log(f"Idle timeout: {IDLE_TIMEOUT}s")
    else:
        log("Idle timeout: disabled")

    # Pre-load VLM if requested
    if args.preload:
        log("Pre-loading VLM model...")
        _load_vlm()

    # Start idle timer
    _reset_idle_timer()

    # Allow port reuse to prevent "Address already in use" on restart
    class ReusableTCPServer(HTTPServer):
        allow_reuse_address = True
        # Do NOT set allow_reuse_port -- on Python 3.12+ it enables SO_REUSEPORT
        # which allows multiple servers on the same port (not what we want).

    _server_instance = ReusableTCPServer((HOST, PORT), VisionHandler)
    log(f"Listening on http://{HOST}:{PORT}")
    log("Endpoints: GET /health, /metrics, /config, /audit, /cache")
    log("Endpoints: POST /ground, /ground_batch, /detect, /parse, /diff, /reload")
    
    _audit.log("server_started", {
        "version": __version__,
        "host": HOST,
        "port": PORT,
        "model_path": MODEL_PATH,
    })

    try:
        _server_instance.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        log("Server stopped")
        _audit.log("server_stopped", {})
        _server_instance.server_close()


if __name__ == "__main__":
    main()
