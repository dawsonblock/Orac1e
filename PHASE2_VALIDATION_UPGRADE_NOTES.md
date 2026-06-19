# Phase 2 Validation Upgrade Notes

## Scope

This pass replaces the flat validation command loop with staged validation profile resolution inside the Oracle runtime.

## What changed

- `CodingValidationCoordinator` now resolves a validation execution plan.
- Plans can come from:
  - explicit `validationCommands` supplied by the operator
  - inferred staged profiles in `configs/validation_profiles/*.json`
- Profile inference checks repo signals in this order:
  - `Package.swift` → `swift`
  - Python markers (`pyproject.toml`, `requirements.txt`, `setup.py`) → `python`
  - `tsconfig.json` → `typescript`
  - `package.json` with TypeScript deps → `typescript`
  - `package.json` without TypeScript deps → `javascript`
  - source file extension fallback
  - `default`
- Validation metadata now records:
  - `validationCommands` as the resolved flattened command list
  - `validationProfileName`
- Validation events now emit:
  - profile name
  - stage count
  - command count
- Validation results now include:
  - `profileName`
  - `stageCount`
  - `resolvedCommands`
  - per-step `stageID`, `stageName`, `profileName`

## Current profile definitions

### Python

- Preflight → `python -m compileall src`
- Targeted tests → `pytest -q tests`

### Swift

- Build → `swift build`
- Tests → `swift test`

### JavaScript / TypeScript / Default

These remain placeholders with empty stage lists. They now load cleanly through the staged profile system, but they still need real repo-aware commands before they should be treated as operational defaults.

## Boundaries

This pass does not prove a successful macOS Swift build. It changes the runtime structure and metadata flow, not the external environment.
