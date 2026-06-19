# P0 remediation notes

Applied fixes:
- approval and rejection now require `awaiting_approval`
- canonical validation runs by default after patch apply
- canonical validation skip requires explicit override via `--allow-skip-canonical-validation` or `ORACLE_ALLOW_SKIP_CANONICAL_VALIDATION=1`
- promotion receipts record `canonical_validation_ran` and `canonical_validation_skip_reason`
- manifest verification no longer counts successful health checks as errors
- added `runtime.apps.validation_worker` compatibility shim
- `PublishGuard` now blocks `release` and `master`
- `PatchArtifact` now accepts omitted optional fields for backward compatibility
