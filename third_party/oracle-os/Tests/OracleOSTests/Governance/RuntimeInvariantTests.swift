import Foundation
import XCTest
@testable import OracleOS

final class RuntimeInvariantTests: XCTestCase {
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

    func test_no_bypass_execution_symbols() throws {
        let sourcesRoot = repositoryRoot().appendingPathComponent("Sources/OracleOS", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            XCTFail("Unable to enumerate sources")
            return
        }

        let forbidden = ["CodeActionGateway", "performAction(", "VerifiedActionExecutor", "ToolDispatcher"]
        var offenders: [String] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift",
                  let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  forbidden.contains(where: content.contains)
            else {
                continue
            }
            offenders.append(fileURL.lastPathComponent)
        }

        XCTAssertTrue(offenders.isEmpty, "Forbidden execution bypass symbols found: \(offenders)")
    }

    func test_loop_is_thin() throws {
        let loopDeclaration = try read("Sources/OracleOS/Execution/Loop/AgentLoop.swift")
        let loopSource = try read("Sources/OracleOS/Execution/Loop/AgentLoop+Run.swift")
        XCTAssertTrue(loopDeclaration.contains("init("))
        XCTAssertTrue(loopDeclaration.contains("intake: any IntentSource"))
        XCTAssertTrue(loopDeclaration.contains("orchestrator: any IntentAPI"))
        XCTAssertFalse(loopDeclaration.contains("observationProvider"))
        XCTAssertFalse(loopDeclaration.contains("executionDriver"))
        XCTAssertFalse(loopSource.contains("Goal("), "AgentLoop+Run should not build goals directly")
        XCTAssertFalse(loopSource.contains("LoopBudget"), "AgentLoop+Run should not manage loop budgets")
        XCTAssertFalse(loopSource.contains("execute("), "AgentLoop+Run should not execute directly")
        XCTAssertFalse(loopSource.contains("decisionCoordinator"), "AgentLoop+Run should not decide directly")
        XCTAssertFalse(loopSource.contains("worldModel.reset("), "AgentLoop+Run should not mutate world state")
    }

    func test_runtime_orchestrator_has_single_pipeline_entry() throws {
        let orchestrator = try read("Sources/OracleOS/Runtime/RuntimeOrchestrator.swift")
        XCTAssertTrue(orchestrator.contains("public func submitIntent"))
        XCTAssertTrue(orchestrator.contains("private func execute"))
        XCTAssertTrue(orchestrator.contains("private func commit"))
        XCTAssertTrue(orchestrator.contains("private func evaluate"))
        XCTAssertFalse(orchestrator.contains("public func execute"))
        XCTAssertFalse(orchestrator.contains("public func commit"))
        XCTAssertFalse(orchestrator.contains("public func evaluate"))
        XCTAssertTrue(orchestrator.contains("snapshotProvider"))
        XCTAssertTrue(orchestrator.contains("await commitCoordinator.snapshot()"))
        XCTAssertTrue(orchestrator.contains("PreconditionsValidator()"))
        XCTAssertFalse(orchestrator.contains("_legacyContext"))
        XCTAssertTrue(orchestrator.contains("try await commit(executionOutcome)"))
    }

    func test_runtime_spine_avoids_direct_process_usage_outside_workspace_runner() throws {
        let spinePaths = [
            "Sources/OracleOS/Runtime/RuntimeOrchestrator.swift",
            "Sources/OracleOS/Execution/VerifiedExecutor.swift",
            "Sources/OracleOS/Execution/Loop/AgentLoop.swift",
            "Sources/OracleOS/Execution/Loop/AgentLoop+Run.swift",
            "Sources/OracleOS/Execution/Routing/CommandRouter.swift",
            "Sources/OracleOS/Execution/Routing/SystemRouter.swift",
            "Sources/OracleOS/Execution/Routing/CodeRouter.swift",
            "Sources/OracleOS/Execution/Routing/UIRouter.swift",
        ]

        for path in spinePaths {
            let source = try read(path)
            XCTAssertFalse(
                source.contains("Process("),
                "Runtime spine file \(path) should not spawn processes directly"
            )
        }
    }
}
