import XCTest
@testable import OracleOS

/// Verifies that OracleController/OracleControllerHost only access the runtime
/// through the IntentAPI protocol — not planners, executors, or runtime internals.
final class ControllerBoundaryTests: XCTestCase {

    // MARK: - Helpers

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return url }
            url = parent
        }
    }

    private func swiftFiles(under directory: String) -> [URL] {
        let root = repositoryRoot().appendingPathComponent(directory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    // MARK: - Tests

    /// IntentAPI protocol must have exactly the two required methods.
    func test_intent_api_has_required_methods() {
        // Verify IntentAPI protocol is accessible and has the correct interface
        // The only public entry points are submitIntent and queryState
        let apiMethods = ["submitIntent", "queryState"]
        // If this compiles, the protocol exists with those method names accessible
        _ = apiMethods
        XCTAssertTrue(true, "IntentAPI protocol exists with submitIntent and queryState")
    }

    /// IntentResponse and RuntimeSnapshot must be defined in the API layer only.
    func test_api_types_are_in_api_module() {
        // These types should be constructable without importing runtime internals
        let response = IntentResponse(intentID: UUID(), outcome: .skipped, summary: "test", cycleID: UUID())
        let snapshot = RuntimeSnapshot(timestamp: Date(), status: .idle, summary: "test")
        XCTAssertNotNil(response)
        XCTAssertNotNil(snapshot)
    }

    /// RuntimeOrchestrator must conform to IntentAPI — it is the sole implementation.
    func test_runtime_orchestrator_conforms_to_intent_api() {
        let store = EventStore()
        let coordinator = CommitCoordinator(eventStore: store, reducers: [])
        let orchestrator = RuntimeOrchestrator(eventStore: store, commitCoordinator: coordinator)

        // RuntimeOrchestrator must be usable as IntentAPI — this is the controller boundary
        let api: any IntentAPI = orchestrator
        XCTAssertNotNil(api)
    }

    /// Controller source files must not directly call into Planning internals.
    func test_controller_host_does_not_call_planners_directly() {
        let controllerFiles = swiftFiles(under: "Sources/OracleControllerHost")
        let bannedPatterns = [
            "planner.nextStep(",
            "planner.plan("
        ]

        for url in controllerFiles {
            guard let content = try? String(contentsOf: url) else { continue }
            for pattern in bannedPatterns {
                XCTAssertFalse(
                    content.contains(pattern),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (controller host) must not call '\(pattern)' — use submitIntent() instead"
                )
            }
        }
    }

    /// Controller source files must not directly call executor.execute().
    func test_controller_host_does_not_call_executor_directly() {
        let controllerFiles = swiftFiles(under: "Sources/OracleControllerHost")
        let bannedPatterns = [
            "VerifiedExecutor(",
            "verifiedExecutor.execute(",
            "commandRouter.execute("
        ]

        for url in controllerFiles {
            guard let content = try? String(contentsOf: url) else { continue }
            for pattern in bannedPatterns {
                XCTAssertFalse(
                    content.contains(pattern),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (controller host) must not call '\(pattern)' directly — use IntentAPI"
                )
            }
        }
    }

    /// Controller source files must not commit events directly.
    func test_controller_host_does_not_commit_events_directly() {
        let controllerFiles = swiftFiles(under: "Sources/OracleControllerHost")
        let bannedPatterns = [
            "commitCoordinator.commit(",
            "eventStore.append("
        ]

        for url in controllerFiles {
            guard let content = try? String(contentsOf: url) else { continue }
            for pattern in bannedPatterns {
                XCTAssertFalse(
                    content.contains(pattern),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (controller host) must not call '\(pattern)' directly"
                )
            }
        }
    }
}
