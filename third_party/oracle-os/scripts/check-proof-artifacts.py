#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

REQUIRED_SCENARIOS = {
    "ui-success": ["README.md"],
    "code-success": ["README.md"],
    "system-success": ["README.md"],
    "forced-postcondition-failure": ["README.md"],
    "replay-determinism": ["README.md"],
}

EXPECTED_MARKERS = [
    "intent",
    "snapshot",
    "event",
    "verifier",
    "verdict",
]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-proof-artifacts.py <ProofArtifacts/timestamp>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    if not root.exists():
        print(f"missing proof directory: {root}", file=sys.stderr)
        return 2

    scenarios_root = root / "scenarios"
    summary: dict[str, dict[str, object]] = {}
    ok = True

    for scenario, required_files in REQUIRED_SCENARIOS.items():
        scenario_dir = scenarios_root / scenario
        scenario_summary: dict[str, object] = {
            "exists": scenario_dir.exists(),
            "required_files": {},
            "has_non_readme_artifacts": False,
        }
        if not scenario_dir.exists():
            ok = False
            summary[scenario] = scenario_summary
            continue

        for filename in required_files:
            present = (scenario_dir / filename).exists()
            scenario_summary["required_files"][filename] = present
            ok = ok and present

        files = [p for p in scenario_dir.rglob("*") if p.is_file()]
        non_readme = [p for p in files if p.name.lower() != "readme.md"]
        scenario_summary["has_non_readme_artifacts"] = bool(non_readme)
        if not non_readme:
            ok = False
        else:
            names = [p.name.lower() for p in non_readme]
            found_markers = {marker: any(marker in name for name in names) for marker in EXPECTED_MARKERS}
            scenario_summary["markers"] = found_markers
            if not all(found_markers.values()):
                ok = False

        summary[scenario] = scenario_summary

    logs_dir = root / "logs"
    summary["logs"] = {
        "exists": logs_dir.exists(),
        "files": sorted([p.name for p in logs_dir.iterdir() if p.is_file()]) if logs_dir.exists() else [],
    }
    if not summary["logs"]["files"]:
        ok = False

    print(json.dumps({"ok": ok, "summary": summary}, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
