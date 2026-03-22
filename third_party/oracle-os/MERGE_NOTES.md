# Oracle-OS merged build

Base:
- Oracle-OS-main 40

Applied on top:
- phase 1 truth-hardening bundle
- phase 2 typed-events bundle
- phase 3 preconditions bundle
- phase 4 independent-verification bundle
- phase 5 cleanup/governance bundle

Imported from Oracle-OS-main 32 as reference material:
- full `docs/` tree under `Reference/oracle32/docs/`
- full `plans/` tree under `Reference/oracle32/plans/`
- full `Tests/OracleOSEvals/` tree under `Reference/oracle32/Tests/OracleOSEvals/`
- `oracle-os-2.0.6-macos-arm64.tar.gz` under `Reference/oracle32/`

Intent:
- keep Oracle-OS-main 40 as the active code base
- keep the phase 1-5 hardening changes as the active code path
- preserve the higher-coverage documentation and eval/archive material from 32 without forcing those files back into the active build surface

Caveats:
- this is a structural merge, not a fully validated macOS build
- the active source tree reflects the phase-5 state over Oracle-OS-main 40
- Oracle-OS-main 32 material is preserved as reference, not reactivated in the active targets
