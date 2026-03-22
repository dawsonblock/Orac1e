#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_ROOT="${ORACLE_VALIDATION_LOG_ROOT:-$PROJECT_ROOT/Diagnostics/validation}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$LOG_ROOT/$STAMP"
SUMMARY="$RUN_DIR/summary.md"

mkdir -p "$RUN_DIR"

run_and_log() {
    local name="$1"
    shift
    echo "==> $name"
    {
        echo "$ $*"
        "$@"
    } >"$RUN_DIR/${name}.log" 2>&1
}

append_summary() {
    printf '%s\n' "$1" >> "$SUMMARY"
}

append_summary "# Oracle OS macOS validation run"
append_summary ""
append_summary "- Timestamp: $STAMP"
append_summary "- Host: $(sw_vers -productVersion 2>/dev/null || echo unknown)"
append_summary "- Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ' || echo unavailable)"
append_summary "- Swift: $(swift --version | head -1)"
append_summary ""

run_and_log swift_version swift --version
run_and_log resolve swift package resolve
run_and_log build_debug swift build -c debug
run_and_log build_release swift build -c release
run_and_log test_all swift test --parallel
run_and_log test_runtime_wiring swift test --filter RuntimeWiringTests
run_and_log test_preconditions swift test --filter PreconditionIntegrationTests
run_and_log test_postconditions swift test --filter PostExecutionVerificationTests
run_and_log build_controller "$PROJECT_ROOT/scripts/build-controller-app.sh" --configuration release --skip-sign --output-dir "$RUN_DIR/dist"
run_and_log build_release_tarball "$PROJECT_ROOT/scripts/build-release.sh" --debug

append_summary "## Automated checks"
append_summary ""
for name in swift_version resolve build_debug build_release test_all test_runtime_wiring test_preconditions test_postconditions build_controller build_release_tarball; do
    if [[ -f "$RUN_DIR/${name}.log" ]]; then
        append_summary "- ${name}: completed"
    else
        append_summary "- ${name}: missing log"
    fi
done

append_summary ""
append_summary "## Manual checks still required"
append_summary ""
append_summary "1. Accessibility-authorized controller launch"
append_summary "2. One successful UI action through the live execution spine"
append_summary "3. One successful code action through the live execution spine"
append_summary "4. One successful system action through the live execution spine"
append_summary "5. One forced postcondition failure through the live execution spine"
append_summary ""
append_summary "See docs/VALIDATION.md for the exact local checklist."

echo "Validation logs written to: $RUN_DIR"
echo "Summary: $SUMMARY"
