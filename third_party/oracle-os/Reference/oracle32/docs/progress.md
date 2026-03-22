# Oracle OS Progress

## Current State

- The repository identity is `OracleOS` with the `oracle` executable.
- The public MCP surface is 22 tools.
- The first verified execution slice is in place for `oracle_click`, `oracle_type`, `oracle_press`, and `oracle_focus`.
- `oracle_context` now carries a canonical `Observation` snapshot in addition to the legacy summary fields.
- Recipes remain replay-only. Trace-to-recipe induction is not integrated.
- `oracle_parse_screen` is available through the vision sidecar, but remains experimental at the Oracle runtime layer.

## Working

- AX-first perception and state inspection
- Coordinate and element-driven actions
- Verified postconditions for focus, value, app frontmost, window title, URL, and appearance/disappearance checks
- JSONL trace recording for verified action attempts
- Recipe replay and CRUD

## Partial

- Observation fusion now merges AX and Chrome CDP candidates conservatively, but it is still not a full world-model ranker
- Vision grounding works for single-target location, but full-screen parsing is not promoted as a supported runtime feature yet
- Policy, world state, planner, loop, skill, and recovery modules exist as scaffolding and early types

## Not Started

- Autonomous loop execution over planner-emitted skills
- Recovery orchestration across ranked target selection failures
- Operational memory, trace-to-recipe induction, validation, and repair
- Benchmark harness and regression reporting

## Near-Term Roadmap

1. Finish Milestones 0-2 cleanly: truth pass, canonical observation, verified execution
2. Extend traces with stronger failure and ranking evidence
3. Integrate world state and bounded loop execution
4. Add structured recovery before learning
