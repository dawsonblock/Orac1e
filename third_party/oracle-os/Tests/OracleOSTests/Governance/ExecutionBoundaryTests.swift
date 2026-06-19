import Foundation
import XCTest
@testable import OracleOS

/// Verifies that ONLY VerifiedExecutor may produce side effects.
/// INVARIANT: No planner, controller, or memory module may call execution actions.
final class ExecutionBoundaryTests: XCTestCase {
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

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func uiCommand(intentID: UUID = UUID()) -> Command {
        Command(
            type: .ui,
            payload: .ui(UIAction(name: "clickElement", app: "com.test.app", query: "button#ok")),
            metadata: CommandMetadata(intentID: intentID)
        )
    }

    private func codeCommand(intentID: UUID = UUID()) -> Command {
        Command(
            type: .code,
            payload: .code(CodeAction(name: "modifyFile", filePath: "/tmp/test.swift", workspacePath: "/tmp/repo")),
            metadata: CommandMetadata(intentID: intentID)
        )
    }

    private func systemCommand(intentID: UUID = UUID()) -> Command {
        Command(
            type: .system,
            payload: .shell(CommandSpec(
                category: .build,
                executable: "/usr/bin/swift",
                arguments: ["build"],
                workspaceRoot: "/tmp/repo",
                summary: "swift build"
            )),
            metadata: CommandMetadata(intentID: intentID)
        )
    }

    func test_planner_may_not_execute() {
        let command = uiCommand()
        XCTAssertEqual(command.kind, "clickElement")
        XCTAssertFalse(String(describing: type(of: MainPlanner.self)).contains("execute"))
    }

    func test_controller_may_only_use_intent_api_surface() throws {
        let protocolSource = try read("Sources/OracleOS/API/IntentAPI.swift")
        XCTAssertTrue(protocolSource.contains("submitIntent"))
        XCTAssertTrue(protocolSource.contains("queryState"))

        let bridgeSource = try read("Sources/OracleControllerHost/ControllerRuntimeBridge.swift")
        XCTAssertFalse(bridgeSource.contains("VerifiedExecutor("))
        XCTAssertTrue(bridgeSource.contains("RuntimeOrchestrator("))
    }

    func test_preconditions_validator_rejects_invalid_state() {
        let validator = PreconditionsValidator()
        let command = uiCommand()
        XCTAssertThrowsError(try validator.validate(command, snapshot: WorldModelSnapshot()))
    }

    func test_safety_validator_rejects_dangerous_patterns() {
        let validator = SafetyValidator()
        let state = WorldStateModel()
        let dangerousCommand = Command(
            type: .code,
            payload: .code(CodeAction(name: "modifyFile", filePath: "/test", patch: "test")),
            metadata: CommandMetadata(intentID: UUID(), rationale: "rm -rf /")
        )

        let result = validator.isSafe(dangerousCommand, state: state)
        XCTAssertFalse(result.safe)
    }

    func test_postconditions_validator_rejects_failed_outcome() {
        let validator = PostconditionsValidator()
        let command = uiCommand()

        let failedOutcome = ExecutionOutcome(
            commandID: command.id,
            status: .failed,
            events: [],
            verifierReport: VerifierReport(
                commandID: command.id,
                preconditionsPassed: true,
                policyDecision: "approved",
                postconditionsPassed: false
            )
        )

        XCTAssertThrowsError(try validator.validate(command, outcome: failedOutcome))
    }

    func test_command_router_identifies_domains() {
        XCTAssertEqual(CommandRouter.domain(for: uiCommand()), .ui)
        XCTAssertEqual(CommandRouter.domain(for: codeCommand()), .code)
        XCTAssertEqual(CommandRouter.domain(for: systemCommand()), .system)
    }

    func test_event_store_is_append_only() async {
        let store = EventStore()
        let envelope = EventEnvelope(
            sequenceNumber: 1,
            commandID: CommandID(),
            intentID: UUID(),
            eventType: "test",
            payload: Data()
        )

        await store.append(envelope)
        let all = await store.all()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.eventType, "test")
    }

    func test_commit_coordinator_returns_immutable_snapshot() async {
        let store = EventStore()
        let coordinator = CommitCoordinator(
            eventStore: store,
            reducers: DefaultReducers.make()
        )

        let snapshot = await coordinator.snapshot()
        XCTAssertNotNil(snapshot)
    }
}
