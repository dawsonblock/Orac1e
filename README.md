# ORACLE Build v5-remediation

> **Supervised Local Coding Runtime** — An authority-controlled coding platform where every change is retrieved, routed, validated, and held for explicit operator approval before touching a canonical repository.

[![Status](https://img.shields.io/badge/status-active-green?style=flat-square)](docs/build_status.md)
[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white)](third_party/oracle-os)
[![Python](https://img.shields.io/badge/Python-3.11%20%7C%203.12-3776AB?style=flat-square&logo=python&logoColor=white)](integration/)
[![Platform](https://img.shields.io/badge/platform-macOS-000000?style=flat-square&logo=apple&logoColor=white)]()
[![License](https://img.shields.io/badge/license-see%20LICENSE-blue?style=flat-square)](LICENSE)

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| **Authority Control** | Oracle OS is the sole canonical worktree owner — workers never write directly to canonical repos |
| **Dual Worker Support** | Interactive Aider worker + bounded autonomous hardened worker |
| **Code Retrieval** | cocoindex-powered semantic code search with retrieval broker |
| **Validation Pipeline** | Multi-stage validation: preflight → lint → targeted tests → full tests (optimized with caching & parallel execution) |
| **Operator Approval** | Every patch awaits explicit approve/reject before apply |
| **Tool Registry** | Manifest-driven tool discovery with health monitoring |
| **SwiftUI Controller** | macOS native UI for managing coding runs |

---

## 🏗️ Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ORACLE OS (Swift)                               │
│                                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Run Ledger  │  │  Event Store │  │ Approval     │  │   Tool       │  │
│  │              │  │              │  │ Store        │  │   Registry   │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Worktree   │  │  Validation  │  │  Mutation    │  │  Retrieval   │  │
│  │  Coordinator │  │  Coordinator │  │  Policy      │  │  Broker      │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────┐
            │ Retrieval │   │   Aider   │   │ Hardened  │
            │  Broker   │   │  Adapter  │   │  Adapter  │
            │ (cocoindex)│   │  (port    │   │  (port     │
            │ (port 8787│   │   8788)   │   │   8789)    │
            └───────────┘   └───────────┘   └───────────┘
```

### Core Design Principles

1. **🔒 Oracle is the only canonical worktree owner**
   - Workers operate on isolated worktrees
   - Canonical repository modifications are exclusively controlled by Oracle

2. **📤 Workers return diffs only**
   - No direct commits or pushes
   - All changes are proposed as patches for review

3. **🔀 Single retrieval broker**
   - All code retrieval flows through the broker
   - No direct sidecar access

4. **✅ Independent re-validation**
   - Every patch is re-validated by Oracle after proposal
   - Worker validation results don't bypass Oracle checks

5. **👤 Explicit operator approval required**
   - Apply only happens after explicit approve/reject

---

## 🔄 How It Works

```
User Request
     │
     ▼
┌─────────────────┐
│   Retrieval     │  ← Semantic code search via cocoindex
│    Broker       │
└─────────────────┘
     │
     ▼
┌─────────────────┐
│  Tool Selection │  ← Oracle selects appropriate tool via ToolRouter
│     & Routing   │
└─────────────────┘
     │
     ▼
┌─────────────────┐
│   Worker        │  ← Aider (interactive) or Hardened (autonomous)
│   Processing    │
└─────────────────┘
     │
     ▼
┌─────────────────┐
│   Validation    │  ← Preflight → Lint → Targeted Tests → Full Tests
│    Pipeline     │
└─────────────────┘
     │
     ▼
┌─────────────────┐
│ Awaiting        │  ← Operator reviews proposed diff
│  Approval       │
└─────────────────┘
     │
     ▼
┌─────────────────┐
│   Apply to      │  ← Only on explicit approval
│  Canonical      │
└─────────────────┘
```

### Run Lifecycle

| State | Description |
|-------|-------------|
| `created` | Run initialized, awaiting processing |
| `retrieving` | Fetching relevant code context |
| `proposing` | Worker generating patch proposal |
| `validating` | Running validation pipeline |
| `awaiting_approval` | Waiting for operator decision |
| `approved` | Operator approved the patch |
| `rejected` | Operator rejected the patch |
| `applied` | Patch merged to canonical (on approval) |

---

## 🚀 Quick Start

### Prerequisites

- **macOS** with Xcode / Swift 5.9+
- **Python 3.11 or 3.12** (3.13+ not yet validated)
- Git

> **Python Version Control:** To use a specific Python interpreter:
> ```bash
> export ORACLE_PYTHON_BIN=python3.12
> ```

### Setup & Launch

```bash
# Step 1: Validate environment
./scripts/check_env.sh

# Step 2: Bootstrap virtual envs, fixture repo, and tool registry
./scripts/bootstrap.sh

# Step 3: Start all services (retrieval → workers → Oracle)
./scripts/start_all.sh

# Step 4: Smoke test
./scripts/smoke_test.sh

# Step 5: Use the CLI
oracle coding help
```

### Service Ports

| Service | Port | Description |
|---------|------|-------------|
| Oracle backend | `8080` | Main Oracle OS backend |
| Retrieval broker | `8787` | cocoindex integration |
| Aider adapter | `8788` | Interactive coding worker |
| Hardened adapter | `8789` | Autonomous coding worker |

### Start Services Individually

```bash
# Start retrieval broker first
./scripts/start_retrieval.sh   # port 8787

# Start coding workers
./scripts/start_workers.sh     # ports 8788, 8789

# Start Oracle backend
./scripts/start_oracle.sh      # swift build + swift run oracle

# Stop all services
./scripts/stop_all.sh
```

---

## ⚙️ Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ORACLE_PYTHON_BIN` | `python3` | Python interpreter path |
| `ORACLE_TOOL_MANIFESTS` | — | Tool manifest directory |
| `ORACLE_HOST` | `localhost` | Oracle backend host |
| `ORACLE_PORT` | `8080` | Oracle backend port |
| `BROKER_PORT` | `8787` | Retrieval broker port |
| `AIDER_PORT` | `8788` | Aider adapter port |
| `HARDENED_PORT` | `8789` | Hardened adapter port |
| `COCOINDEX_REPO_PATH` | — | Path to cocoindex repo |
| `ORACLE_SKIP_PIP_INSTALL` | `0` | Set to `1` to skip pip |
| `ORACLE_ALLOW_UNSUPPORTED_PYTHON` | `0` | Set to `1` to bypass version check |

---

## 📁 Project Structure

```
oracle-build-v5-remediation/
├── configs/                        # Configuration files
│   ├── app.env                     # Application settings
│   ├── approval_policy.json        # Approval rules
│   ├── command_policy.json         # Command restrictions
│   ├── mutation_policy.json        # Mutation guidelines
│   ├── tool_policy.json            # Tool usage policies
│   ├── ports.env                   # Port assignments
│   ├── routing_profiles/           # Routing configurations
│   └── validation_profiles/         # Validation rules by language
│
├── docs/                           # Architecture & design docs
│   ├── architecture.md             # System architecture
│   ├── build_blueprint.md          # Product design
│   ├── approval_flow.md           # Approval mechanics
│   ├── security_model.md          # Trust boundaries
│   └── troubleshooting.md         # Common issues
│
├── integration/                    # Python adapters & SDK
│   ├── tool_sdk/                   # Tool development kit
│   ├── retrieval_broker/           # Code retrieval service
│   ├── tools/                      # Tool implementations
│   │   ├── aider/                 # Aider adapter
│   │   ├── hardened/              # Hardened worker
│   │   └── cocoindex/             # Code search
│   └── worker_aider/              # Aider runner
│       worker_hardened/           # Hardened runner
│
├── scripts/                       # Automation scripts
│   ├── bootstrap.sh               # Initial setup
│   ├── start_all.sh               # Launch all services
│   ├── start_retrieval.sh         # Start broker
│   ├── start_workers.sh           # Start workers
│   ├── start_oracle.sh            # Start Oracle
│   ├── check_env.sh               # Validate prerequisites
│   └── coding_run_promotion.py    # Patch application
│
├── tests/                         # Test suites
│   ├── e2e/                       # End-to-end tests
│   └── integration/               # Integration tests
│
├── third_party/                   # External dependencies
│   ├── oracle-os/                 # Oracle OS (Swift)
│   │   ├── Sources/OracleOS/     # Core OS implementation
│   │   ├── Sources/OracleController/ # macOS UI
│   │   └── ProjectMemory/        # Architecture decisions
│   ├── aider/                    # Aider LLM coding tool
│   ├── code-agent-runtime/       # Validation runtime
│   │   ├── apps/                 # Worker applications
│   │   ├── runtime/              # Core runtime
│   │   └── domains/              # Language domains
│   └── cocoindex-code/          # Code search engine
│
└── workspace/                    # Generated runtime state
    ├── artifacts/               # Runtime artifacts
    └── (repos, worktrees, runs, logs)
```

---

## 🛠️ Tool Model

### Tool Discovery

Tools are discovered via `tool.json` manifests in each tool's directory. Oracle uses `ToolRouter` to select tools by capability and invokes them through a generic `/invoke` envelope.

### Tool Types

| Kind | Description |
|------|-------------|
| `worker` | Code generation and editing |
| `retrieval` | Code search and context retrieval |
| `validator` | Code validation and testing |
| `action` | Side effects and operations |

### Available Tools

| Tool | Type | Description |
|------|------|-------------|
| `aider` | worker | Interactive LLM-powered coding |
| `hardened` | worker | Autonomous bounded coding worker |
| `cocoindex` | retrieval | Semantic code search |

### Adding New Tools

See [`docs/extension_guide.md`](docs/extension_guide.md) for instructions on adding custom tools.

---

## 📊 Validation Pipeline

The validation pipeline ensures code quality before operator review:

```
┌─────────────┐
│  Preflight │  ← Patch structure validation
└─────────────┘
       │
       ▼
┌─────────────┐
│    Lint     │  ← Language-specific linting (cached)
└─────────────┘
       │
       ▼
┌─────────────┐
│  Targeted   │  ← Relevant test selection (cached)
│    Tests    │
└─────────────┘
       │
       ▼
┌─────────────┐
│   Full      │  ← Complete test suite (selective)
│   Tests     │
└─────────────┘
```

### Optimization Features

- **Parallel Execution**: Lint and targeted tests run concurrently
- **Result Caching**: ValidationCache avoids redundant computation
- **Adaptive Timeouts**: Timeouts scale based on patch size
- **Smart Skip Logic**: Full tests skipped for low-risk patches (docs, config, refactoring)

---

## 📜 Version History

### v6 (Current)

- Restored Oracle Controller Coding workspace UI with SwiftUI components
- Python run server is the single state-mutation authority for coding runs
- Normalized API responses with enriched run details
- Idempotency guards on approve/reject endpoints
- Integrated coding run list, detail, approve, and reject in Controller UI

### v5

- Restored `oracle coding list|show|run|approve|reject` CLI entrypoints
- Added `OracleCodingRuntime.swift` — Swift wrapper preserving v4 integrated run path
- Approve/reject prefer the v4 run server bridge
- Manifest-driven tool discovery with registry health

See [`docs/merge_notes_v5.md`](docs/merge_notes_v5.md) and [`oracle_build_v6_implementation_plan.md`](oracle_build_v6_implementation_plan.md) for full details.

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [`docs/architecture.md`](docs/architecture.md) | Authority model and runtime shape |
| [`docs/build_blueprint.md`](docs/build_blueprint.md) | Product design and core flows |
| [`docs/startup_order.md`](docs/startup_order.md) | Step-by-step service startup |
| [`docs/build_order.md`](docs/build_order.md) | Build dependency order |
| [`docs/approval_flow.md`](docs/approval_flow.md) | Approval and rejection mechanics |
| [`docs/worktree_model.md`](docs/worktree_model.md) | Worktree isolation model |
| [`docs/security_model.md`](docs/security_model.md) | Authority and trust boundaries |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Common issues and fixes |
| [`docs/ports_and_env.md`](docs/ports_and_env.md) | Full port and env var reference |
| [`docs/validation_v5.md`](docs/validation_v5.md) | Validation pipeline details |

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -am 'Add new feature'`
4. Push to branch: `git push origin feature/my-feature`
5. Submit a pull request

---

> **⚠️ Status:** Active - Oracle Build v6 Controller UI integration complete.
> See [`docs/release_truth.md`](docs/release_truth.md) for supported features.
