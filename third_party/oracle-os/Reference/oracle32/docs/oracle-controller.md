# Oracle Controller

Oracle Controller is the native local operator console for Oracle OS.

It now supports both developer and packaged-app flows:

- SwiftPM/Xcode workspace development
- standalone `Oracle Controller.app`
- downloadable `Oracle-Controller-<version>.dmg`

## Components

- `OracleController`: SwiftUI macOS dashboard
- `OracleControllerHost`: local helper host that links `OracleOS` and owns runtime execution
- `OracleControllerShared`: typed IPC models shared by the app and the host
- `OracleController.xcworkspace`: Xcode workspace entry point

## What It Does

- live snapshot-based monitor for the current app
- manual action control for focus, click, type, press, scroll, and wait
- recipe library with create, duplicate, edit, save, delete, and run
- trace session browser with per-step verification, hashes, and artifact links
- health panel for permissions, sidecar state, trace directory, and recipe directory
- approvals and risky-action visibility
- guided onboarding for permissions and first-run setup
- diagnostics export and app-data reveal/reset actions
- optional vision bootstrap install and repair from the UI

## Runtime Model

- one controller app launch starts one local host process
- one host process owns one runtime trace session
- the UI never calls heavy OracleOS APIs directly
- verified actions and recipe runs flow through `OracleControllerHost`
- packaged builds write to `~/Library/Application Support/Oracle OS/`
- legacy `~/.oracle-os` data is migrated when present

## Packaged App Layout

The packaged product is:

- `Oracle Controller.app`
- embedded helper: `Contents/Helpers/OracleControllerHost`
- bundled help/release notes/resources under `Contents/Resources/`
- optional bundled vision bootstrap assets under `Contents/Resources/VisionBootstrap/`

Primary user-owned storage:

- `~/Library/Application Support/Oracle OS/Traces/`
- `~/Library/Application Support/Oracle OS/Recipes/`
- `~/Library/Application Support/Oracle OS/Approvals/`
- `~/Library/Application Support/Oracle OS/ProjectMemory/`
- `~/Library/Application Support/Oracle OS/Experiments/`
- `~/Library/Logs/Oracle OS/`

## First Launch

The first-launch wizard walks through:

1. product overview
2. Accessibility permission setup
3. Screen Recording permission setup
4. bundled host/runtime health
5. optional vision bootstrap setup
6. sample recipes and quick-start actions
7. ready-to-launch confirmation

## Opening It

### In Xcode

```bash
open OracleController.xcworkspace
```

Run the `Oracle Controller` or `Oracle Controller DMG` scheme from the workspace.

### From SwiftPM

```bash
swift build
./.build/debug/OracleController
```

If the controller cannot locate the host binary automatically, set:

```bash
export ORACLE_CONTROLLER_HOST_PATH="$PWD/.build/debug/OracleControllerHost"
```

### Build the packaged app and DMG

```bash
./scripts/build-controller-app.sh --configuration release
./scripts/create-controller-dmg.sh --configuration release
```

Unsigned development artifacts can be built with:

```bash
./scripts/build-controller-app.sh --configuration debug --skip-sign
./scripts/create-controller-dmg.sh --configuration debug --skip-sign
```

### Release signing and notarization

The release pipeline expects Developer ID and notary credentials.

Local notarization helper:

```bash
./scripts/notarize-controller-release.sh "dist/Oracle Controller.app"
./scripts/notarize-controller-release.sh dist/Oracle-Controller-*.dmg
```

CI automation lives in:

- `.github/workflows/controller-release.yml`

## Notes

- The controller is local-only and human-supervised.
- Risky actions still require explicit confirmation in the UI.
- Monitoring is low-frequency snapshot refresh, not streaming video.
- The app uses the existing recipe JSON schema and does not change MCP tool names.
- Vision is optional and experimental in the packaged product.
