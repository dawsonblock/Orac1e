# Oracle-OS vNext — Runtime Baseline

## Build Environment
- Swift Toolchain: 5.9+
- macOS Version: 13.0+
- Package Manager: Swift Package Manager

## Current State
- Source Files: 200+
- Test Files: 50+
- Dependencies: See Package.resolved

## Known Issues
- None currently tracked

## Architecture Status
The vNext refactor establishes:
- One execution spine (RuntimeOrchestrator)
- Event-sourced state (EventStore + Reducers)
- Controller boundary (IntentAPI only)
- Planner contracts (no execution)

## Migration Phases
1. ✅ Execution spine established
2. ✅ Event system implemented  
3. ✅ State layer restructured
4. ⏳ Planning surface shrinking
5. ⏳ Executor hardening

## Exit Criteria
- Single runtime path from intent to side effect
- Single state path from events to reducers
- Controller bypass eliminated
