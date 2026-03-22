# Full Repo Layout

```text
oracle-build/
├── docs/
├── scripts/
├── configs/
├── workspace/
├── tests/
├── integration/
│   ├── contracts/
│   ├── shared_py/
│   ├── retrieval_broker/
│   ├── worker_aider/
│   ├── worker_hardened/
│   ├── tool_sdk/
│   └── tools/
└── third_party/
    ├── oracle-os/
    ├── aider/
    ├── code-agent-runtime/
    └── cocoindex-code/
```

## Top-level intent

- `docs/`: human-readable system truth
- `scripts/`: bootstrap, startup, shutdown, smoke, sync
- `configs/`: routing, policy, ports, validation profiles
- `workspace/`: mutable runtime state, worktrees, runs, artifacts, logs
- `tests/`: integration and end-to-end tests
- `integration/`: Python adapters, broker, contracts, tool SDK
- `third_party/`: mostly intact upstream repos

## Authority boundary

Anything responsible for run state, event history, worktree lifecycle, approval, or final patch apply belongs to Oracle.

Anything responsible for adapting a tool, translating requests, or normalizing responses belongs in `integration/`.

Anything responsible for actual upstream model or tool internals stays in `third_party/`.
