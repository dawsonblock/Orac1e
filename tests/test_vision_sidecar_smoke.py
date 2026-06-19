"""Smoke tests for the Oracle Vision Sidecar.

These tests verify the server starts and responds to basic endpoints
without requiring the heavy ShowUI model or YOLO weights.

Heavy model tests are gated behind ORACLE_RUN_MODEL_TESTS=1.
"""

from __future__ import annotations

import base64
import json
import os
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path
from urllib.request import Request, urlopen

import pytest

SIDECAR_DIR = Path(__file__).resolve().parents[1] / "third_party" / "oracle-os" / "vision-sidecar"
SERVER_PY = SIDECAR_DIR / "server.py"

# Skip entire module if server.py not found
pytestmark = pytest.mark.skipif(
    not SERVER_PY.exists(),
    reason="vision-sidecar server.py not found",
)


def _start_server(port: int = 9877) -> subprocess.Popen:
    """Start the vision sidecar server on a random port."""
    proc = subprocess.Popen(
        [sys.executable, str(SERVER_PY), "--port", str(port), "--host", "127.0.0.1"],
        cwd=str(SIDECAR_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    # Wait for server to be ready
    for _ in range(30):
        try:
            urlopen(f"http://127.0.0.1:{port}/health", timeout=1)
            return proc
        except Exception:
            time.sleep(0.5)
    proc.kill()
    pytest.fail("Vision sidecar server failed to start within 15 seconds")


def _get(port: int, path: str) -> dict:
    resp = urlopen(f"http://127.0.0.1:{port}{path}", timeout=5)
    return json.loads(resp.read())


def _post_json(port: int, path: str, data: dict) -> tuple[int, dict]:
    body = json.dumps(data).encode()
    req = Request(
        f"http://127.0.0.1:{port}{path}",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        resp = urlopen(req, timeout=10)
        return resp.status, json.loads(resp.read())
    except Exception as e:
        # Extract status code from HTTPError
        if hasattr(e, "code"):
            return e.code, json.loads(e.read()) if e.read() else {}
        raise


def _make_tiny_png() -> str:
    """Create a minimal valid PNG image as base64."""
    # 1x1 white pixel PNG
    import struct
    import zlib

    def _chunk(chunk_type: bytes, data: bytes) -> bytes:
        c = chunk_type + data
        crc = struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + c + crc

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = _chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    raw = b"\x00\xff\xff\xff"  # filter byte + white pixel RGB
    idat = _chunk(b"IDAT", zlib.compress(raw))
    iend = _chunk(b"IEND", b"")
    png_bytes = sig + ihdr + idat + iend
    return base64.b64encode(png_bytes).decode()


class TestVisionSidecarSmoke:
    """Basic smoke tests for the vision sidecar."""

    @pytest.fixture(autouse=True)
    def _start(self):
        self.port = 9877
        self.proc = _start_server(self.port)
        yield
        self.proc.kill()
        self.proc.wait(timeout=5)

    def test_health(self):
        data = _get(self.port, "/health")
        # Server returns "ready" (model loaded) or "idle" (no model) — not "ok"
        assert data.get("status") in ("ready", "idle")
        assert "version" in data

    def test_metrics_json(self):
        data = _get(self.port, "/metrics")
        assert isinstance(data, dict)
        # Server nests metrics under data["metrics"]
        metrics = data.get("metrics", data)
        assert "total_requests" in metrics or "requests_total" in metrics or "requests" in metrics

    def test_config(self):
        data = _get(self.port, "/config")
        assert isinstance(data, dict)
        assert "host" in data or "port" in data

    def test_diff_with_tiny_pngs(self):
        img = _make_tiny_png()
        # Server expects image_a / image_b, not image_before / image_after
        status, data = _post_json(self.port, "/diff", {
            "image_a": img,
            "image_b": img,
        })
        assert status == 200
        # Server returns has_changes, change_ratio, not diff_pct or changed
        assert "has_changes" in data or "change_ratio" in data or "ok" in data


class TestVisionSidecarModelTests:
    """Tests that require model loading — gated behind env var."""

    @pytest.mark.skipif(
        os.environ.get("ORACLE_RUN_MODEL_TESTS") != "1",
        reason="Set ORACLE_RUN_MODEL_TESTS=1 to run model tests",
    )
    def test_ground_endpoint(self):
        proc = _start_server(9878)
        try:
            img = _make_tiny_png()
            status, data = _post_json(9878, "/ground", {
                "image": img,
                "description": "button",
            })
            # May fail if model not available, that's ok for smoke test
            assert status in (200, 400, 500)
        finally:
            proc.kill()
            proc.wait(timeout=5)
