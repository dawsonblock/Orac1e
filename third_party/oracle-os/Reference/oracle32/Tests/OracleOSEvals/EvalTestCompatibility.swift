import Foundation
@testable import OracleOS

extension MainPlanner {
    func plan(failure: FailureClass, state: ReasoningPlanningState) -> [RecoveryPlan] {
        RecoveryPlanner().plan(failure: failure, state: state)
    }
}
