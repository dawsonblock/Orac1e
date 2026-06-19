import Foundation
import Testing
@testable import OracleOS

@Suite("Execution Enforcement")
struct ExecutionEnforcementTests {

    // MARK: - executedThroughExecutor flag

    @Test("ActionResult defaults executedThroughExecutor to false")
    func defaultFalse() {
        let result = ActionResult(success: true)
        #expect(result.executedThroughExecutor == false)
    }

    @Test("ActionResult preserves executedThroughExecutor when set true")
    func explicitTrue() {
        let result = ActionResult(
            success: true,
            verified: true,
            executedThroughExecutor: true
        )
        #expect(result.executedThroughExecutor == true)
    }

    @Test("ActionResult toDict includes executed_through_executor")
    func toDictIncludesFlag() {
        let result = ActionResult(
            success: true,
            executedThroughExecutor: true
        )
        let dict = result.toDict()
        #expect(dict["executed_through_executor"] as? Bool == true)
    }

    @Test("ActionResult from(dict:) reads executed_through_executor")
    func fromDictReadsFlag() {
        let dict: [String: Any] = [
            "success": true,
            "executed_through_executor": true,
        ]
        let result = ActionResult.from(dict: dict)
        #expect(result?.executedThroughExecutor == true)
    }

    @Test("ActionResult from(dict:) defaults flag to false when absent")
    func fromDictDefaultsFalse() {
        let dict: [String: Any] = ["success": true]
        let result = ActionResult.from(dict: dict)
        #expect(result?.executedThroughExecutor == false)
    }

    @Test("ActionResult round-trips executedThroughExecutor through Codable")
    func codableRoundTrip() throws {
        let original = ActionResult(
            success: true,
            verified: true,
            executedThroughExecutor: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        #expect(decoded.executedThroughExecutor == true)
    }
}
