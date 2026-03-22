# Contributing to Oracle OS

Oracle OS is open source and we welcome contributions.

## What We Need Help With

### Recipes

The most impactful contribution is a new recipe. Pick an app, figure out the workflow, save it as a recipe JSON, test it 3+ times, and submit a PR.

Good recipe candidates:

- Slack: send a message, reply to a thread
- Google Calendar: create an event
- Finder: organize files, create folders
- System Settings: toggle settings
- Any web app: login, fill forms, extract data

### Testing on Different Apps

Oracle OS should work with every app. Test it with apps you use daily and report what works and what doesn't. File issues with:

- Which app and version
- What tool you called
- What happened vs what you expected
- The output from `oracle doctor`

### Bug Fixes

Check the [issues](https://github.com/dawsonblock/Oracle-OS/issues) page. Issues labeled `good first issue` are a great starting point.

## Development Setup

```bash
git clone https://github.com/dawsonblock/Oracle-OS.git
cd Oracle-OS
swift build
```

**All major refactors must run `swift test --filter OracleOSEvals` and pass the baseline.**

Requirements:

- macOS 14+
- Swift 5.9+ (install via [swiftly](https://github.com/swiftlang/swiftly))
- Accessibility permission for your terminal app
- Screen Recording permission (optional, for screenshots)

The project vendors [AXorcist](https://github.com/steipete/AXorcist) in `Vendor/AXorcist`, so no extra local checkout is required.

## Project Structure

```text
Sources/
├── OracleOS/                   # Runtime, planning, memory, MCP, tools
├── OracleController/           # Native SwiftUI/AppKit controller app
├── OracleControllerHost/       # Local host process bundled with controller
├── OracleControllerShared/     # Shared controller types
└── oracle/                     # CLI entry point and setup tooling

Tests/
├── OracleOSTests/              # Runtime and governance-focused tests
├── OracleOSEvals/              # Baseline/eval regression coverage
├── OracleControllerTests/      # Controller and shared-model tests
└── Fixtures/                   # Test fixtures

Supporting directories:
- `docs/` — architecture, governance, status, and rollout docs
- `ProjectMemory/` — accepted decisions, open problems, and risk tracking
- `recipes/` — JSON recipes for repeatable workflows
- `scripts/` — local build, packaging, and release automation
```

## Writing a Recipe

Recipes are JSON files stored in `~/.oracle-os/recipes/`. Here's the structure:

```json
{
    "schema_version": 2,
    "name": "my-recipe",
    "description": "What this recipe does",
    "app": "Google Chrome",
    "params": {
        "query": {
            "type": "string",
            "description": "What to search for",
            "required": true
        }
    },
    "preconditions": {
        "app_running": "Google Chrome",
        "url_contains": "example.com"
    },
    "steps": [
        {
            "id": 1,
            "action": "click",
            "target": {
                "criteria": [{"attribute": "AXRole", "value": "AXButton"}],
                "computedNameContains": "Search"
            },
            "wait_after": {
                "condition": "elementExists",
                "value": "Results",
                "timeout": 5
            },
            "note": "Click the search button"
        }
    ],
    "on_failure": "stop"
}
```

**Actions:** click, type, press, hotkey, focus, scroll, wait

**Wait conditions:** elementExists, elementGone, urlContains, titleContains, urlChanged, titleChanged, delay

**Tips:**

- Use `computedNameContains` for fuzzy matching ("Compose" matches "Compose" button)
- Add `criteria` with `AXRole` to narrow matches (e.g., only buttons)
- Always include `"criteria": []` even if empty (required by the Locator decoder)
- Use `wait_after` instead of fixed delays
- Test your recipe at least 3 times before submitting

## Code Style

- Swift 6.2 with strict concurrency
- All logging to stderr (stdout is the MCP protocol channel)
- No force unwraps except in tests
- Functions over 80 lines get split
- Errors tell the agent what to do next, not just what went wrong

## Commit Messages

- Concise but informative
- Anyone reading the git log should understand what changed
- No AI attribution lines
