# Oracle Controller Help

Oracle Controller is the packaged local console for Oracle OS.

## First Launch

1. Open the app from `/Applications`.
2. Complete the guided setup wizard.
3. Grant Accessibility and Screen Recording when prompted.
4. Use the Control workspace for safe manual actions.
5. Use Recipes, Traces, Health, and Settings for deeper runtime work.

## Data Locations

- Application Support: `~/Library/Application Support/Oracle OS/`
- Logs: `~/Library/Logs/Oracle OS/`

## Vision

Vision is optional and experimental. The app can install the packaged vision bootstrap into Application Support, but the base controller works without it.

## Safety

Oracle Controller keeps the existing Oracle OS execution truth path:

`UI -> bundled host -> RuntimeExecutionDriver -> RuntimeOrchestrator.submitIntent -> VerifiedExecutor.execute -> CommitCoordinator -> Trace/Graph/Memory`

Risky actions remain approval-gated.
