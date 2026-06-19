"""Command policy enforcement for validation commands.

Every validation command must pass through validate_command() before execution.
Commands are checked against allow_prefixes and deny_prefixes from the policy file.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_POLICY_PATH = ROOT / "configs" / "command_policy.json"


@dataclass(frozen=True)
class CommandDecision:
    allowed: bool
    reason: str


def load_policy(path: Path | None = None) -> dict:
    """Load command policy from JSON file."""
    if path is None:
        path = DEFAULT_POLICY_PATH
    if not path.exists():
        return {"allow_prefixes": [], "deny_prefixes": []}
    return json.loads(path.read_text(encoding="utf-8"))


def validate_command(command: str, policy: dict) -> CommandDecision:
    """Check whether a command is allowed by policy.

    Order of evaluation:
    1. Empty command → denied
    2. Deny prefixes checked first (deny wins over allow)
    3. Allow prefixes checked second
    4. No match → denied (fail-closed)
    """
    command = command.strip()
    if not command:
        return CommandDecision(False, "empty command")

    for denied in policy.get("deny_prefixes", []):
        if command.startswith(denied):
            return CommandDecision(False, f"denied prefix: {denied}")

    for allowed in policy.get("allow_prefixes", []):
        if command.startswith(allowed):
            return CommandDecision(True, f"allowed prefix: {allowed}")

    return CommandDecision(False, "command does not match allowlist")
