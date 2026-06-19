# Contracts

Hard contracts are defined in `domains/code/contracts.yaml`.

Current hard denies cover:

- default branch push
- merge actions
- forbidden path edits
- network access during tests
- workspace escape

The arbiter evaluates contracts before publishing anything.
