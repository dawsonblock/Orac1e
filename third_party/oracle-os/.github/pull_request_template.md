# Oracle-OS Pull Request

## Summary
Describe the change clearly.

What capability or behavior improves?

---

# Governance Checklist

## Execution Boundary

- [ ] All world-changing actions pass through `VerifiedExecutor.execute(_:)`
- [ ] No direct host automation calls bypass executor
- [ ] No direct browser automation bypass executor
- [ ] Postcondition verification exists
- [ ] Transition emission still occurs

---

## Loop / Planner Boundaries

### AgentLoop

- [ ] AgentLoop only orchestrates
- [ ] No subsystem logic added
- [ ] No graph/memory manipulation inside loop

### Planner

- [ ] Planner remains decision arbiter
- [ ] No repo graph construction added
- [ ] No workflow synthesis logic added
- [ ] No direct execution added

---

## Knowledge Promotion

- [ ] No one-off event becomes stable knowledge
- [ ] Promotion thresholds respected
- [ ] Replay validation used where relevant
- [ ] Contradiction detection present

---

## Recovery

- [ ] Recovery actions use verified execution
- [ ] Recovery classification exists
- [ ] Recovery results feed learning systems
- [ ] Recovery cannot loop indefinitely

---

## Target Resolution

- [ ] All UI actions use ranked target selection
- [ ] Ambiguity detection implemented
- [ ] No first-match shortcuts

---

## Memory Influence

- [ ] Memory bias is bounded
- [ ] Stale evidence decays
- [ ] Contradictory evidence can override

---

## Experiment Safety

- [ ] Experiment candidates are bounded
- [ ] Results verified before applying
- [ ] Experiment loops terminate

---

## Evaluation

- [ ] Tests added or updated
- [ ] Integration tests pass
- [ ] Relevant benchmarks identified

---

# Tests Added

List new tests.

---

# Expected Behavioral Impact

Example:

- fewer recovery loops
- faster workflow reuse
- improved patch success rate

---

# Architecture Impact

Describe which subsystem this change affects:

- Runtime
- Planning
- Memory
- Workflow
- Code Intelligence
- Automation
- Recovery
- Evaluation
