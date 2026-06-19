# Architecture

## Authority model

Oracle owns:
- run creation
- worktree lifecycle
- validation
- event log
- approval log
- final patch application

Workers own:
- proposing diffs
- emitting warnings and artifacts

cocoindex owns:
- code indexing and search

## Runtime shape

```text
user
  -> Oracle OS
      -> retrieval broker -> cocoindex
      -> worker router -> aider | code-agent-runtime-hardened
      -> worktree coordinator
      -> patch apply service
      -> validation coordinator
      -> run ledger / event store / approval store
```

## Control invariants

1. Oracle is the only canonical worktree owner.
2. Workers return diffs. They do not commit or push.
3. Retrieval enters through one broker.
4. Every patch is revalidated in Oracle after proposal.
