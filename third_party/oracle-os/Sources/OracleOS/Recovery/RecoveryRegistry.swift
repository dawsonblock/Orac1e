public final class RecoveryRegistry {

    private var strategies: [FailureClass: [any RecoveryStrategy]] = [:]

    public func register(
        failure: FailureClass,
        strategy: any RecoveryStrategy
    ) {
        strategies[failure, default: []].append(strategy)
    }

    public func strategy(
        for failure: FailureClass
    ) -> (any RecoveryStrategy)? {
        strategies[failure]?.first
    }

    public func strategies(
        for failure: FailureClass
    ) -> [any RecoveryStrategy] {
        strategies[failure] ?? []
    }

    @MainActor
    public static func live() -> RecoveryRegistry {
        let registry = RecoveryRegistry()
        registry.register(failure: .wrongFocus, strategy: RefocusAppStrategy())
        registry.register(failure: .staleObservation, strategy: RefreshObservationStrategy())
        registry.register(failure: .modalBlocking, strategy: DismissModalStrategy())
        registry.register(failure: .navigationFailed, strategy: RetryStrategy())
        registry.register(failure: .verificationFailed, strategy: RetryStrategy())
        registry.register(failure: .elementNotFound, strategy: AlternateElementStrategy())
        registry.register(failure: .elementAmbiguous, strategy: AlternateElementStrategy())
        registry.register(failure: .actionFailed, strategy: RetryStrategy())
        registry.register(failure: .buildFailed, strategy: RefreshIndexStrategy())
        registry.register(failure: .buildFailed, strategy: RerunFocusedTestsStrategy())
        registry.register(failure: .testFailed, strategy: RerunFocusedTestsStrategy())
        registry.register(failure: .patchApplyFailed, strategy: RevertPatchStrategy())
        registry.register(failure: .patchApplyFailed, strategy: RefreshIndexStrategy())
        registry.register(failure: .workspaceScopeViolation, strategy: RefreshIndexStrategy())
        registry.register(failure: .noRelevantFiles, strategy: RefreshIndexStrategy())
        registry.register(failure: .ambiguousEditTarget, strategy: RefreshIndexStrategy())
        registry.register(failure: .gitPolicyBlocked, strategy: RefreshIndexStrategy())
        registry.register(failure: .targetMissing, strategy: AlternateElementStrategy())
        registry.register(failure: .targetMissing, strategy: RefreshObservationStrategy())
        registry.register(failure: .permissionBlocked, strategy: DismissModalStrategy())
        registry.register(failure: .permissionBlocked, strategy: RetryStrategy())
        registry.register(failure: .unexpectedDialog, strategy: DismissModalStrategy())
        registry.register(failure: .unexpectedDialog, strategy: RetryStrategy())
        registry.register(failure: .environmentMismatch, strategy: RefreshIndexStrategy())
        registry.register(failure: .environmentMismatch, strategy: RetryStrategy())
        registry.register(failure: .loopStalled, strategy: StallRecoveryStrategy())
        return registry
    }
}
