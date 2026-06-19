#!/usr/bin/env python3
"""Architecture guard for Oracle-OS.

Scans Swift source files for forbidden type references that would violate
the architectural boundary rules defined in docs/GOVERNANCE.md and
docs/runtime_invariants.md. Uses word-boundary regex and skips comments.

Prevents:
- AgentLoop absorbing subsystem internals (Rule 2)
- Planner absorbing subsystem internals (Rule 3)
"""

import os
import re
import sys

FORBIDDEN_REFERENCES = {
    "AgentLoop.swift": [
        "WorkflowSynthesizer",
        "PatchRanker",
        "DOMIndexer",
        "BrowserTargetResolver",
        "MemoryPromotionPolicy",
        "MemoryScorer",
    ],
    "Planner.swift": [
        "WorkflowSynthesizer",
        "DOMFlattener",
        "VerifiedExecutor",
        "PatchImpactPredictor",
    ],
}


def scan_file(path):
    with open(path) as f:
        lines = f.readlines()

    violations = []

    name = os.path.basename(path)

    if name in FORBIDDEN_REFERENCES:
        for item in FORBIDDEN_REFERENCES[name]:
            pattern = re.compile(r"\b" + re.escape(item) + r"\b")
            for lineno, line in enumerate(lines, 1):
                stripped = line.lstrip()
                if stripped.startswith("//"):
                    continue
                if pattern.search(line):
                    violations.append(item)
                    break

    return violations


def scan_repo(root):
    violations = []

    for dirpath, _, files in os.walk(root):
        for file in files:
            if file.endswith(".swift"):
                path = os.path.join(dirpath, file)
                v = scan_file(path)

                if v:
                    violations.append((path, v))

    return violations


if __name__ == "__main__":
    root = "Sources"

    if not os.path.isdir(root):
        print("Sources directory not found, skipping architecture guard.")
        sys.exit(0)

    violations = scan_repo(root)

    if violations:
        print("\nARCHITECTURE VIOLATIONS FOUND\n")

        for path, items in violations:
            print(path)
            for item in items:
                print("  forbidden:", item)

        sys.exit(1)

    print("Architecture guard passed.")
