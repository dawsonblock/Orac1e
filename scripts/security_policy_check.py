#!/usr/bin/env python3
"""
Security Policy Validator

Automatically validates that security policies are correctly configured
and haven't been inadvertently weakened.

Checks:
- BLOCKED_PATH_PREFIXES in diff_utils.py
- Mutation policy constraints
- Command policy restrictions
- Tool policy configurations
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# Add project root to path
ROOT = Path(__file__).resolve().parents[1]  # scripts/ is 1 level down from root
os.chdir(ROOT)
sys.path.insert(0, str(ROOT))

errors: list[str] = []
warnings: list[str] = []


def ok(label: str) -> None:
    print(f"  [OK] {label}")


def fail(label: str, msg: str) -> None:
    errors.append(f"{label}: {msg}")
    print(f"  [FAIL] {label}: {msg}")


def warn(label: str, msg: str) -> None:
    warnings.append(f"{label}: {msg}")
    print(f"  [WARN] {label}: {msg}")


# ── 1. BLOCKED_PATH_PREFIXES ──────────────────────────────────────
try:
    from integration.shared_py.diff_utils import BLOCKED_PATH_PREFIXES

    # Required blocked prefixes for security
    required_blocked = [
        ".git/",
        ".github/",
        "secrets/",
        "infra/",
        "deploy/",
    ]

    # Check all required prefixes are present
    for prefix in required_blocked:
        if prefix not in BLOCKED_PATH_PREFIXES:
            fail("blocked_paths", f"Missing required blocked prefix: {prefix}")
        else:
            ok(f"blocked_paths: {prefix}")

    # Check no dangerous prefixes were removed
    if len(BLOCKED_PATH_PREFIXES) < len(required_blocked):
        warn("blocked_paths", "Fewer blocked prefixes than expected")

except Exception as e:
    fail("blocked_paths", str(e))


# ── 2. Mutation Policy ────────────────────────────────────────────
try:
    mutation_policy_path = ROOT / "configs" / "mutation_policy.json"
    if mutation_policy_path.exists():
        policy = json.loads(mutation_policy_path.read_text(encoding="utf-8"))

        # Check max_files constraint
        max_files = policy.get("max_files", 0)
        if max_files > 50:
            fail("mutation_policy", f"max_files too high: {max_files} (max recommended: 50)")
        else:
            ok(f"mutation_policy: max_files={max_files}")

        # Check max_changed_lines constraint
        max_lines = policy.get("max_changed_lines", 0)
        if max_lines > 500:
            fail("mutation_policy", f"max_changed_lines too high: {max_lines} (max recommended: 500)")
        else:
            ok(f"mutation_policy: max_changed_lines={max_lines}")

        # Check blocked_prefixes in policy
        policy_blocked = policy.get("blocked_prefixes", [])
        for prefix in required_blocked:
            if prefix not in policy_blocked:
                fail("mutation_policy", f"Missing blocked prefix in policy: {prefix}")
            else:
                ok(f"mutation_policy: {prefix}")
    else:
        warn("mutation_policy", "mutation_policy.json not found")

except Exception as e:
    fail("mutation_policy", str(e))


# ── 3. Command Policy ─────────────────────────────────────────────
try:
    command_policy_path = ROOT / "configs" / "command_policy.json"
    if command_policy_path.exists():
        policy = json.loads(command_policy_path.read_text(encoding="utf-8"))

        # Check deny list contains dangerous commands
        deny_list = policy.get("deny", [])
        dangerous_commands = ["rm -rf", "sudo", "chmod 777", "curl | bash"]

        for cmd in dangerous_commands:
            if cmd not in deny_list:
                warn("command_policy", f"Consider adding to deny list: {cmd}")

        ok("command_policy: loaded")

except Exception as e:
    fail("command_policy", str(e))


# ── 4. Tool Policy ────────────────────────────────────────────────
try:
    tool_policy_path = ROOT / "configs" / "tool_policy.json"
    if tool_policy_path.exists():
        policy = json.loads(tool_policy_path.read_text(encoding="utf-8"))

        # Check that risky tools are restricted
        tools = policy.get("tools", {})
        risky_tools = ["shell", "exec", "eval"]

        for tool in risky_tools:
            if tool in tools:
                tool_config = tools[tool]
                if not tool_config.get("restricted", False):
                    warn("tool_policy", f"Tool '{tool}' is not restricted")

        ok("tool_policy: loaded")

except Exception as e:
    fail("tool_policy", str(e))


# ── 5. Sandbox Configuration ──────────────────────────────────────
try:
    from integration.worker_hardened.sandbox import SandboxConfig

    config = SandboxConfig()

    # Check resource limits
    if config.max_cpu_time > 60:
        fail("sandbox", f"max_cpu_time too high: {config.max_cpu_time}s (max recommended: 60s)")
    else:
        ok(f"sandbox: max_cpu_time={config.max_cpu_time}s")

    if config.max_memory > 1024 * 1024 * 1024:  # 1 GB
        fail("sandbox", f"max_memory too high: {config.max_memory} bytes (max recommended: 1GB)")
    else:
        ok(f"sandbox: max_memory={config.max_memory // (1024*1024)}MB")

    # Check that dangerous paths are blocked
    dangerous_paths = ["/etc", "/usr", "/var", "/root"]
    for path in dangerous_paths:
        if path not in config.blocked_paths:
            fail("sandbox", f"Missing blocked path: {path}")
        else:
            ok(f"sandbox: {path} blocked")

except Exception as e:
    fail("sandbox", str(e))


# ── 6. Vision Sidecar Security ────────────────────────────────────
try:
    vision_server_path = ROOT / "third_party" / "oracle-os" / "vision-sidecar" / "server.py"
    if vision_server_path.exists():
        content = vision_server_path.read_text(encoding="utf-8")

        # Check localhost binding
        if "127.0.0.1" not in content:
            fail("vision_sidecar", "Missing localhost binding (127.0.0.1)")
        else:
            ok("vision_sidecar: localhost binding")

        # Check rate limiting
        if "RateLimiter" not in content:
            fail("vision_sidecar", "Missing rate limiting")
        else:
            ok("vision_sidecar: rate limiting")

        # Check input validation
        if "validate_image_input" not in content:
            fail("vision_sidecar", "Missing image validation")
        else:
            ok("vision_sidecar: image validation")

        # Check security headers
        if "X-Content-Type-Options" not in content:
            fail("vision_sidecar", "Missing security headers")
        else:
            ok("vision_sidecar: security headers")

except Exception as e:
    fail("vision_sidecar", str(e))


# ── Summary ───────────────────────────────────────────────────────
print()
if errors:
    print(f"FAILED — {len(errors)} error(s):")
    for err in errors:
        print(f"  • {err}")
    sys.exit(1)
elif warnings:
    print(f"PASSED with {len(warnings)} warning(s):")
    for warn in warnings:
        print(f"  • {warn}")
    sys.exit(0)
else:
    print("All security policies validated ✓")
    sys.exit(0)
