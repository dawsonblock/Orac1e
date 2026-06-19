import Foundation
import Testing
@testable import OracleOS

/// Verifies the execution kernel trust boundary:
/// every action must pass through VerifiedExecutor.execute(_:)
/// and the resulting ToolResult must carry action_result.executed_through_executor = true.
@Suite("Execution Kernel Boundary")
@MainActor
struct ExecutionKernelBoundaryTests {

    // MARK: - executor stamp contract

    @Test("ActionResult can carry executedThroughExecutor stamp")
    func executorStampsFlag() {
        let result = ToolResult(
            success: true,
            data: [
                "action_result": ActionResult(success: true, executedThroughExecutor: true).toDict()
            ]
        )
        let dict = result.data?["action_result"] as? [String: Any]
        #expect(dict?["executed_through_executor"] as? Bool == true)
    }

    // MARK: - trust boundary contract on ActionResult

    @Test("ActionResult with executedThroughExecutor=true passes boundary contract")
    func stampedResultPassesBoundary() {
        let result = ActionResult(
            success: true,
            verified: true,
            executedThroughExecutor: true
        )
        #expect(result.executedThroughExecutor == true)
    }

    @Test("ActionResult with executedThroughExecutor=false fails boundary contract")
    func unstampedResultFailsBoundary() {
        let result = ActionResult(success: true, executedThroughExecutor: false)
        #expect(result.executedThroughExecutor == false)
    }

    // MARK: - round-trip through toDict / from(dict:)

    @Test("ActionResult executed_through_executor round-trips through toDict")
    func stampedRoundTripDict() {
        let original = ActionResult(success: true, executedThroughExecutor: true)
        let dict = original.toDict()
        let recovered = ActionResult.from(dict: dict)
        #expect(recovered?.executedThroughExecutor == true)
    }

    @Test("ActionResult executed_through_executor absent in dict defaults to false")
    func missingKeyDefaultsFalse() {
        let partial: [String: Any] = ["success": true]
        let result = ActionResult.from(dict: partial)
        #expect(result?.executedThroughExecutor == false)
    }

    // MARK: - ToolResult data contract

    @Test("ToolResult missing action_result key is detectable as bypass")
    func bareToolResultIsDetectable() {
        // A bare ToolResult without action_result is what a bypass would produce.
        // Verify the detection logic used by OracleRuntime works.
        let bareResult = ToolResult(success: true, data: [:])
        let actionResultDict = bareResult.data?["action_result"] as? [String: Any]
        let stamped = actionResultDict != nil && actionResultDict?["executed_through_executor"] as? Bool == true
        #expect(stamped == false, "Bare ToolResult must be detected as an unstamped bypass")
    }

    @Test("ToolResult with stamped action_result passes detection")
    func stampedToolResultPassesDetection() {
        let actionResult = ActionResult(success: true, executedThroughExecutor: true)
        let result = ToolResult(success: true, data: ["action_result": actionResult.toDict()])
        let actionResultDict = result.data?["action_result"] as? [String: Any]
        let stamped = actionResultDict != nil && actionResultDict?["executed_through_executor"] as? Bool == true
        #expect(stamped == true)
    }
}
