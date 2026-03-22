# Failure modes

Typical failures:
- broker unavailable
- unhealthy worker
- malformed diff
- policy rejection
- validation failure
- apply failure
- missing manifests

Expected behavior:
- persist the run
- append failure events
- keep artifacts
- leave canonical repo untouched
