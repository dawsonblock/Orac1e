# Security model

Oracle is the only authority.

Workers can propose changes but cannot:
- approve themselves
- apply directly to the canonical repo
- own run state
- bypass mutation policy

The generic tool layer does not change that. It only standardizes discovery and invocation.
