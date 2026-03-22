import Foundation
import XCTest
@testable import OracleOS

final class PreconditionIntegrationTests: XCTestCase {
    func test_verified_executor_returns_precondition_failed_before_routing() async throws {
        let executor = VerifiedExecutor(
            snapshotProvider: { WorldModelSnapshot() }
        )

        let command = Command(
            type: .ui,
            payload: .ui(UIAction(name: "clickElement", app: "com.test.app", query: "button#ok")),
            metadata: CommandMetadata(intentID: UUID())
        )

        let outcome = try await executor.execute(command)

        XCTAssertEqual(outcome.status, .preconditionFailed)
        XCTAssertEqual(outcome.verifierReport.preconditionsPassed, false)
        XCTAssertEqual(outcome.verifierReport.policyDecision, "not_evaluated")
    }
}
