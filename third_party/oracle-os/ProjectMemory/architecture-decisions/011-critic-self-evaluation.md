# ADR 011: Critic-Driven Self-Evaluation

## Decision

Every executed action is followed by a critic pass that evaluates the outcome by comparing pre- and post-state. The critic classifies outcomes as SUCCESS, PARTIAL_SUCCESS, FAILURE, or UNKNOWN and drives recovery signals, graph updates, and state memory.

## Reason

Enables the agent to correct itself without external intervention. Provides recovery signals to the planner. Drives knowledge promotion and demotion in the graph. Creates traceable evidence for replay and debugging.

## Tradeoffs

- **Latency**: Additional evaluation step adds overhead
- **Complexity**: Requires well-defined success criteria per action
- **Accuracy**: Critic classification may not always be correct

## Affected Modules

- `OracleOS/Execution/Critic/CriticLoop.swift` - self-evaluation
- `OracleOS/Planning/GraphSearch/` - graph updates
- `OracleOS/StateMemory/StateMemoryIndex` - state memory updates

## Evidence

- [ARCHITECTURE.md:189-217](../../ARCHITECTURE.md) - critic loop documentation

## Source

Oracle OS runtime, autonomous agent improvement
