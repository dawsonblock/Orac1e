# Replay determinism

Replay determinism is the minimum proof that the committed-state story is real instead of decorative.

## What must be true

For a fixed persisted event stream:

- replay from zero produces the same final snapshot every time
- replaying the same batch twice does not change the final snapshot
- sequence ordering is monotonic and preserved
- reducers do not append duplicate signals or notes on duplicate replay

## What to capture

From one successful runtime session, persist:

- the raw event stream in order
- the final snapshot produced by the live run
- the final snapshot produced by replay 1
- the final snapshot produced by replay 2

Then compare:

- live final snapshot vs replay 1
- replay 1 vs replay 2
- replay 2 vs duplicate-batch replay

## Failure conditions

Any of these means the commit layer is still weak:

- cycle counts drift upward on repeated replay
- notes accumulate duplicate entries
- knowledge signals grow on repeated replay
- active app, URL, repository state, or test counts differ between replays
- sequence numbers move backward or skip unexpectedly

## Acceptance rule

Do not call the runtime deterministic until the saved snapshots match and the proof artifacts are retained under `ProofArtifacts/`.
