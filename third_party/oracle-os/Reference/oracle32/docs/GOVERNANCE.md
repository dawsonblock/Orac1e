# Oracle OS Governance

This document is the primary contract for how Oracle OS is allowed to grow.

It is normative. When code and docs disagree, this file wins.

## Purpose

Oracle OS already has many subsystems:

- runtime orchestration
- verified execution
- graph learning
- project memory
- experiments
- architecture review
- recovery
- code and OS planners

The failure mode is no longer "missing architecture." The failure mode is letting those layers drift until the system stops learning from trustworthy execution.

This governance spec defines the non-negotiable rules that keep the runtime coherent.

## Rule Set

### G1 Execution Truth Path

All meaningful OS and code mutations must flow through one hard path:

`intent -> policy -> verified execution -> trace -> runtime-managed graph/memory/recovery update`

Hard-fail requirements:

- no UI mutation outside runtime-managed execution
- no code command execution outside `WorkspaceRunner`
- no graph/memory mutation from planners or skills
- no direct stable knowledge writes from execution call sites

Allowed:

- planners choose actions
- skills resolve targets or workspace actions
- architecture engine emits findings and proposals

Forbidden:

- direct click/type dispatch from skills
- direct process execution from planners
- direct graph promotion from experiments or recovery code

### G2 Reusable Knowledge vs Episode Residue

Oracle OS must not confuse history with reusable knowledge.

Two classifications are required:

- `KnowledgeTier`: trust/evidence level for control knowledge
  - `exploration`
  - `candidate`
  - `stable`
  - `experiment`
  - `recovery`
- `KnowledgeClass`: storage class for learned information
  - `reusable`
  - `parameter`
  - `episode`

Hard-fail requirements:

- experiment evidence never promotes directly to stable
- recovery evidence never promotes directly to stable
- episode residue never enters canonical project memory

Promotion defaults for stable graph:

- attempts `>= 5`
- success rate `>= 0.8`
- postcondition consistency `>= 0.9`
- ambiguity within threshold

### G3 Hierarchical Planning / Local Execution

Planning chooses intent. Execution resolves locally.

Layer responsibilities:

- goal and workflow layers choose direction
- graph/code/OS planners choose the next bounded step
- skills resolve semantic targets or workspace commands
- verified execution performs and verifies the step

Hard-fail requirements:

- planners must not execute directly
- target-bearing OS skills must resolve through ranking and world query
- executor must not absorb policy/orchestration logic

### G4 Recovery as First-Class Execution Mode

Recovery is a tracked mode, not an exception afterthought.

Requirements:

- recovery actions carry explicit recovery tagging
- recovery traces remain separable from nominal traces
- recovery graph edges stay in `recovery` tier
- recovery success and failure are tracked independently

Hard-fail requirements:

- recovery-tagged transitions cannot be treated as stable knowledge
- recovery logic must not silently leak into nominal planner or executor paths

### G5 Evaluation Before Architecture Growth

Architecture expansion only counts when evals or governance tests improve with it.

Requirements:

- every new mutating runtime path adds governance coverage
- every new stable promotion path adds promotion coverage
- every new recovery path adds recovery-tagging coverage
- planner/control-flow growth adds at least one relevant eval scenario

Hard-fail default:

- high-impact architecture work without matching eval or governance coverage

Advisory default:

- cycles
- boundary erosion
- large-file drift
- module creep below hard-fail threshold

## Enforcement Levels

### Hard-fail

These must fail tests or be rejected in code:

- workspace escape for code actions
- direct stable writes from execution paths
- experiment/recovery evidence treated as stable
- target-resolution bypass in target-bearing OS skills
- explicit execution-path bypasses

### Advisory

These should produce governance findings and controller visibility:

- dependency cycles
- repeated boundary erosion
- recovery logic drift
- architecture growth without enough local cleanup context

## Mutation Boundaries

### May mutate the world

- `OracleRuntime`
- `VerifiedActionExecutor` only through its delegated execution closure
- `WorkspaceRunner` for direct process execution in the code domain
- runtime-managed code file operations inside the verified execution path

### May not mutate the world

- planners
- skills
- architecture engine
- project-memory query/index layers
- graph promotion policy

## Knowledge Storage Rules

### Canonical stores

- stable/candidate graph in SQLite
- canonical project memory in repo-local `ProjectMemory/`

### Non-canonical stores

- trace files
- artifacts
- experiment sandboxes
- episode-residue project-memory artifacts under `.oracle/`

## Recovery Rules

- recovery remains bounded
- recovery evidence is reusable only after a future explicit promotion policy
- this milestone keeps recovery evidence non-stable by rule

## CI Gate

CI must run:

- `swift build`
- `swift test`

Any governance hard-fail in tests blocks the change.

## Future Work Constraint

Do not add:

- neural policies
- workflow promotion
- belief-state reasoning
- distributed execution

until these governance rules are holding and measured by tests/evals.
