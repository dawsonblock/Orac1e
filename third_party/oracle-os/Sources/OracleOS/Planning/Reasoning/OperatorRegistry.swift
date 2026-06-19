import Foundation

public final class OperatorRegistry: @unchecked Sendable {
    public static let shared = OperatorRegistry()

    private var operators: [Operator]

    public init(operators: [Operator] = ReasoningOperatorKind.allCases.map { Operator(kind: $0) }) {
        self.operators = operators
    }

    public func register(_ op: Operator) {
        operators.append(op)
    }

    public func available(for state: ReasoningPlanningState) -> [Operator] {
        operators
            .filter { $0.precondition(state) }
            .sorted { lhs, rhs in
                priority(for: lhs, state: state) < priority(for: rhs, state: state)
            }
    }

    private func priority(for op: Operator, state: ReasoningPlanningState) -> Int {
        switch op.kind {
        case .dismissModal where state.modalPresent:
            return 0
        case .focusWindow where state.targetApplication != nil && state.activeApplication != state.targetApplication:
            return 1
        case .openApplication where state.targetApplication != nil && state.activeApplication != state.targetApplication:
            return 2
        case .navigateBrowser where state.targetDomain != nil && state.currentDomain != state.targetDomain:
            return 3
        case .rerunTests where state.patchApplied:
            return 4
        case .runTests, .buildProject:
            return 5
        case .applyPatch:
            return 6
        case .clickTarget:
            return 7
        case .revertPatch, .rollbackPatch:
            return 8
        case .retryWithAlternateTarget:
            return 9
        case .restartApplication:
            return 10
        default:
            return 11
        }
    }
}
