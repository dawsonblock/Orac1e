# Build status

This workspace is an upgraded scaffold.

Implemented in source form:
- adapter layer
- broker layer
- manifest-driven tool layer
- Oracle-side integration stubs and discovery path
- operator docs and test scaffolding

Not validated here:
- full Oracle Swift build on macOS
- end-to-end live run on a real repo


## March 2026 correction

- run server added on port 8790
- workspaces materialize under `workspace/repos/*` as git-backed repos
- validated runs now stop at `awaiting_approval`
- approval now has a promotion path into the canonical repo
- promotion receipts and validation artifacts persist under `workspace/runs/`
