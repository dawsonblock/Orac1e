# Tool model

Each tool declares itself with `tool.json`. Oracle discovers tools through `ToolRegistry`, selects them by capability through `ToolRouter`, and invokes them through a generic `/invoke` envelope.

Current tool kinds:
- worker
- retrieval
- validator
- action

Current live tools:
- aider
- hardened
- cocoindex
