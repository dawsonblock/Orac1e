# Oracle Build v6 - Release Truth

This document defines the supported and not-yet-supported features for Oracle Build v6.

## Supported Features

### Controller UI Integration
- **Coding Workspace View**: SwiftUI-based interface for managing coding runs in Oracle Controller
- **Coding Inspector View**: Panel for starting new coding runs and approving/rejecting pending runs
- **Run List**: Display of all coding runs with status, task, mode, and timestamps
- **Run Detail**: Enriched view showing events, approvals, and promotions for each run
- **Run Controls**: Start, approve, and reject coding runs directly from the UI

### Python Backend
- **Run Server API**: FastAPI-based server for managing coding runs
- **Normalized Responses**: All endpoints return enriched detail with events, approvals, and promotions
- **Idempotent Operations**: Approve/reject endpoints include idempotency guards
- **Health Endpoint**: Standardized `{"status": "ok"}` response format

### Integration Components
- **Retrieval Broker**: Ranked code search results with path and score
- **Aider Adapter**: Returns diff and touched files from code proposals
- **Hardened Adapter**: Enforces allowed paths budget for code changes
- **Tool Registry**: Manifest-driven tool discovery and loading

### Testing
- **Broker Tests**: Validates ranked results with path and score
- **Aider Adapter Tests**: Validates diff extraction and touched path detection
- **Hardened Adapter Tests**: Validates path budget enforcement
- **Tool Registry Tests**: Validates manifest loading and capability filtering

## Not Yet Supported Features

### Advanced Capabilities
- **Real-time Run Updates**: WebSocket/polling for live run status changes
- **Run Rollback**: Ability to revert applied changes
- **Batch Operations**: Multi-run approval/rejection
- **Run Templates**: Pre-configured coding run templates

### Extended Integrations
- **External CI/CD Integration**: GitHub Actions, GitLab CI triggers
- **Remote Worker Support**: Distributed worker nodes
- **Enhanced Retrieval**: Semantic search, multi-language indexing
- **Vision Sidecar**: Advanced vision-based UI interaction

### Observability
- **Distributed Tracing**: Cross-service trace correlation
- **Metrics Dashboard**: Prometheus/Grafana integration
- **Audit Logging**: Detailed operation audit trail

### Security
- **Role-Based Access**: User roles and permissions
- **API Key Management**: External API authentication
- **Audit Exports**: Compliance-ready log exports

## Known Limitations

1. **macOS Only**: Oracle Controller requires macOS for full functionality
2. **Python 3.11+**: Requires Python 3.11 or 3.12 (3.13+ not validated)
3. **Swift 5.9+**: Requires Swift 5.9 or later for Oracle OS components
4. **Local Execution**: Designed for supervised local operation, not remote deployment

## Status Definitions

| Status | Meaning |
| --- | --- |
| `running` | Run is actively being processed |
| `awaiting_approval` | Run completed, pending operator approval |
| `applied` | Run approved and changes committed to canonical repo |
| `rejected` | Run rejected by operator |
| `failed` | Run failed during processing |

## Migration Notes

v6 introduces the following breaking changes from v5:
- Python run server is now the single authority for run state mutations
- API responses include `_events`, `_approvals`, and `_promotions` fields
- Approve/reject endpoints return enriched run detail instead of simple acknowledgment

## Next Steps

For upcoming features and roadmap, see the project issue tracker.