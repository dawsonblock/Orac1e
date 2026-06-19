import Foundation
import XCTest

final class RuntimeWiringTests: XCTestCase {
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

    func test_verified_executor_owns_independent_verification_dependencies() throws {
        let source = try read("Sources/OracleOS/Execution/VerifiedExecutor.swift")
        XCTAssertTrue(source.contains("postExecutionObserver"))
        XCTAssertTrue(source.contains("outcomeVerifier"))
        XCTAssertTrue(source.contains("commandRouter.execute"))
    }

    func test_command_router_no_longer_writes_verifier_truth() throws {
        let source = try read("Sources/OracleOS/Execution/Routing/CommandRouter.swift")
        XCTAssertFalse(source.contains("postconditionsPassed: true"))
        XCTAssertFalse(source.contains("VerifierReport("))
    }

    func test_live_entry_points_use_default_reducers() throws {
        let controller = try read("Sources/OracleControllerHost/ControllerRuntimeBridge.swift")
        let mcp = try read("Sources/OracleOS/MCP/MCPDispatch.swift")
        XCTAssertTrue(controller.contains("DefaultReducers.make()"))
        XCTAssertTrue(mcp.contains("DefaultReducers.make()"))
        XCTAssertFalse(controller.contains("reducers: []"))
        XCTAssertFalse(mcp.contains("reducers: []"))
    }
}
