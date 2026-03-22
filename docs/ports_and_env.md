# Ports and environment

Default local ports:
- Oracle backend: 8080
- retrieval broker / cocoindex path: 8787
- aider adapter: 8788
- hardened adapter: 8789

Important env vars:
- `ORACLE_PYTHON_BIN`
- `ORACLE_TOOL_MANIFESTS`
- `ORACLE_HOST`
- `ORACLE_PORT`
- `BROKER_PORT`
- `AIDER_PORT`
- `HARDENED_PORT`
- `COCOINDEX_REPO_PATH`
- `CODE_AGENT_REPO_PATH`
- `AIDER_REPO_PATH`

Optional bootstrap flags:
- `ORACLE_SKIP_PIP_INSTALL=1` — create venvs and fixture repo without installing packages
- `ORACLE_ALLOW_UNSUPPORTED_PYTHON=1` — bypass the Python 3.11/3.12 recommendation and force the selected interpreter
