import Foundation

public struct RecoveryStrategyEntry: Sendable {
    public let name: String
    public let applicableFailures: [FailureClass]
    public let description: String
    public let baseCost: Double
    public let risk: Double

    public init(
        name: String,
        applicableFailures: [FailureClass],
        description: String,
        baseCost: Double = 1.0,
        risk: Double = 0.1
    ) {
        self.name = name
        self.applicableFailures = applicableFailures
        self.description = description
        self.baseCost = baseCost
        self.risk = risk
    }
}

public final class RecoveryStrategyLibrary: @unchecked Sendable {
    public static let shared = RecoveryStrategyLibrary()

    public let entries: [RecoveryStrategyEntry]

    public init(entries: [RecoveryStrategyEntry]? = nil) {
        self.entries = entries ?? Self.defaultEntries
    }

    public func applicable(for failure: FailureClass) -> [RecoveryStrategyEntry] {
        entries
            .filter { $0.applicableFailures.contains(failure) }
            .sorted { $0.baseCost < $1.baseCost }
    }

    public func entry(named name: String) -> RecoveryStrategyEntry? {
        entries.first { $0.name == name }
    }

    private static let defaultEntries: [RecoveryStrategyEntry] = [
        RecoveryStrategyEntry(
            name: "retry_with_new_target",
            applicableFailures: [.elementNotFound, .elementAmbiguous, .targetMissing, .staleObservation],
            description: "Retry the action with a re-resolved or alternate target element.",
            baseCost: 0.6,
            risk: 0.08
        ),
        RecoveryStrategyEntry(
            name: "refocus_window",
            applicableFailures: [.wrongFocus, .navigationFailed],
            description: "Bring the correct application window to focus.",
            baseCost: 0.4,
            risk: 0.03
        ),
        RecoveryStrategyEntry(
            name: "dismiss_dialog",
            applicableFailures: [.modalBlocking, .unexpectedDialog],
            description: "Dismiss an unexpected modal dialog or alert.",
            baseCost: 0.3,
            risk: 0.02
        ),
        RecoveryStrategyEntry(
            name: "reopen_context",
            applicableFailures: [.navigationFailed, .staleObservation, .wrongFocus],
            description: "Re-navigate to the expected context or page.",
            baseCost: 0.8,
            risk: 0.06
        ),
        RecoveryStrategyEntry(
            name: "restart_application",
            applicableFailures: [.wrongFocus, .environmentMismatch, .actionFailed],
            description: "Restart the target application to clear state.",
            baseCost: 1.5,
            risk: 0.15
        ),
        RecoveryStrategyEntry(
            name: "rollback_patch",
            applicableFailures: [.patchApplyFailed, .buildFailed, .testFailed],
            description: "Rollback the most recent patch and restore clean state.",
            baseCost: 1.2,
            risk: 0.08
        ),
        RecoveryStrategyEntry(
            name: "rebuild_environment",
            applicableFailures: [.environmentMismatch, .buildFailed],
            description: "Clean and rebuild the development environment.",
            baseCost: 2.0,
            risk: 0.20
        ),
        RecoveryStrategyEntry(
            name: "retry_workflow",
            applicableFailures: [.workflowReplayFailure, .verificationFailed],
            description: "Re-parameterize and retry the workflow from the beginning.",
            baseCost: 0.9,
            risk: 0.10
        ),
    ]
}
