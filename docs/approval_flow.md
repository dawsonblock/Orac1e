# Approval flow

A normal run ends in `awaiting_approval` after retrieval, proposal, policy checks, and validation.

Only then may an operator:
- approve
- reject

Approval triggers Oracle-side apply logic. Rejection records a final state without touching the canonical repo.
