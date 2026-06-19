import Foundation
import Testing
@testable import OracleOS

@Suite("Verified Recovery Path")
struct VerifiedRecoveryPathTests {

    @Test("Recovery plans carry failure class context")
    func recoveryPlansCarryContext() {
        let plan = RecoveryPlan(
            failureClass: .modalBlocking,
            recoveryOperators: [Operator(kind: .dismissModal)],
            estimatedRecoveryProbability: 0.8,
            notes: ["dismiss modal for recovery"]
        )
        #expect(plan.failureClass == .modalBlocking)
        #expect(!plan.recoveryOperators.isEmpty)
    }

    @Test("Recovery operator kinds map to valid operator registry entries")
    func recoveryOperatorKindsMapToRegistry() {
        for op in RecoveryOperator.defaults {
            let operatorInstance = Operator(kind: op.operatorKind)
            #expect(!operatorInstance.name.isEmpty)
            #expect(operatorInstance.baseCost >= 0)
        }
    }

    @Test("All default recovery strategies have non-empty descriptions")
    func allDefaultStrategiesHaveDescriptions() {
        for entry in RecoveryStrategyLibrary.shared.entries {
            #expect(!entry.name.isEmpty)
            #expect(!entry.description.isEmpty)
            #expect(!entry.applicableFailures.isEmpty)
        }
    }

    @Test("Failure classifier produces consistent classification")
    func failureClassifierConsistency() {
        let first = FailureClassifier.classify(errorDescription: "Target element not found")
        let second = FailureClassifier.classify(errorDescription: "Target element not found")
        #expect(first.failureClass == second.failureClass)
        #expect(first.confidence == second.confidence)
    }
}
