import Foundation

public struct RecoveryOperator: Sendable {
    public let name: String
    public let operatorKind: ReasoningOperatorKind
    public let targetFailureClasses: [FailureClass]
    public let baseCost: Double
    public let risk: Double

    public init(
        name: String,
        operatorKind: ReasoningOperatorKind,
        targetFailureClasses: [FailureClass],
        baseCost: Double = 1.0,
        risk: Double = 0.1
    ) {
        self.name = name
        self.operatorKind = operatorKind
        self.targetFailureClasses = targetFailureClasses
        self.baseCost = baseCost
        self.risk = risk
    }

    public static let defaults: [RecoveryOperator] = [
        RecoveryOperator(
            name: "retry_alternate_target",
            operatorKind: .retryWithAlternateTarget,
            targetFailureClasses: [.elementNotFound, .elementAmbiguous, .targetMissing, .staleObservation],
            baseCost: 0.7,
            risk: 0.1
        ),
        RecoveryOperator(
            name: "focus_window",
            operatorKind: .focusWindow,
            targetFailureClasses: [.wrongFocus, .navigationFailed],
            baseCost: 0.3,
            risk: 0.02
        ),
        RecoveryOperator(
            name: "dismiss_modal",
            operatorKind: .dismissModal,
            targetFailureClasses: [.modalBlocking, .unexpectedDialog],
            baseCost: 0.4,
            risk: 0.02
        ),
        RecoveryOperator(
            name: "restart_app",
            operatorKind: .restartApplication,
            targetFailureClasses: [.wrongFocus, .environmentMismatch, .actionFailed],
            baseCost: 1.5,
            risk: 0.15
        ),
        RecoveryOperator(
            name: "rollback_patch",
            operatorKind: .rollbackPatch,
            targetFailureClasses: [.patchApplyFailed, .buildFailed, .testFailed],
            baseCost: 1.2,
            risk: 0.08
        ),
        RecoveryOperator(
            name: "navigate_browser",
            operatorKind: .navigateBrowser,
            targetFailureClasses: [.navigationFailed],
            baseCost: 0.8,
            risk: 0.06
        ),
        RecoveryOperator(
            name: "revert_patch",
            operatorKind: .revertPatch,
            targetFailureClasses: [.patchApplyFailed],
            baseCost: 1.4,
            risk: 0.1
        ),
        RecoveryOperator(
            name: "refocus_for_workflow",
            operatorKind: .focusWindow,
            targetFailureClasses: [.workflowReplayFailure],
            baseCost: 0.5,
            risk: 0.04
        ),
    ]

    public static func applicable(for failure: FailureClass) -> [RecoveryOperator] {
        defaults.filter { $0.targetFailureClasses.contains(failure) }
            .sorted { $0.baseCost < $1.baseCost }
    }
}
