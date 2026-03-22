# Strategy Baseline Metrics

> **Date**: 2026-03-13
> **Branch**: `strategy-top-level-upgrade`

## Metrics Template

These metrics should be captured before and after the strategy-top-level-upgrade changes to measure impact.

| Metric | Pre-Upgrade | Post-Upgrade | Δ |
|---|---|---|---|
| Task success rate | — | — | — |
| Average steps to completion | — | — | — |
| Workflow reuse rate | — | — | — |
| Memory hit rate | — | — | — |
| Wrong-target rate | — | — | — |
| Recovery count (per task) | — | — | — |
| Patch success rate | — | — | — |
| Cross-strategy contamination | — | — | — |

## How to Capture

Run the eval set and populate the table above. Optionally save raw data to `Diagnostics/strategy_baseline.json`.

```bash
# Example: run tests and capture strategy diagnostics
swift test --filter "Strategy" 2>&1 | tee Diagnostics/strategy_test_output.txt
```

## What Changed

The **strategy-top-level-upgrade** enforces:

1. `SelectedStrategy` is **non-optional** in all consumer APIs — strategy is mandatory before planning
2. `TaskEdge` carries explicit `operatorFamily` metadata
3. `GraphScorer` includes a `strategyFit` signal (weight 0.12)
4. Recovery mode is bounded to `recovery` + `graphEdge` families only
5. All LLM prompts include strategy context unconditionally
6. Workflow matching/retrieval is always scoped by strategy
7. Memory bias always incorporates strategy-specific rules
