import XCTest
@testable import OracleOS

/// Verifies layer import boundaries across major modules.
/// Scanning Swift import statements ensures Planning, Execution, Controller
/// layers never directly cross-contaminate each other.
final class LayerImportRulesTests: XCTestCase {

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

    private func allImports(in url: URL) -> [String] {
        guard let content = try? String(contentsOf: url) else { return [] }
        return content.components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Planner boundary

    /// Planning files must not directly import execution action handlers.
    /// Planners return Commands — they never import execution-side handlers.
    func test_planning_cannot_import_execution_actions() {
        let planningFiles = swiftFiles(under: "Sources/OracleOS/Planning")
        let bannedImports = ["import VerifiedExecutor", "import PreconditionsValidator"]

        for url in planningFiles {
            let imports = allImports(in: url)
            for banned in bannedImports {
                XCTAssertFalse(
                    imports.contains(banned),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (planner) must not import '\(banned)'"
                )
            }
        }
    }

    /// Execution files must not import Planning top-level planning logic.
    func test_execution_cannot_import_planning() {
        let executionFiles = swiftFiles(under: "Sources/OracleOS/Execution")
        let bannedImports = ["import MainPlanner", "import OSPlanningStrategy", "import CodePlanningStrategy"]

        for url in executionFiles {
            let imports = allImports(in: url)
            for banned in bannedImports {
                XCTAssertFalse(
                    imports.contains(banned),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (executor) must not import '\(banned)'"
                )
            }
        }
    }

    /// API module (IntentAPI, IntentRequest, etc.) must not import Runtime internals.
    func test_api_module_does_not_import_runtime_internals() {
        let apiFiles = swiftFiles(under: "Sources/OracleOS/API")
        let bannedImports = ["import RuntimeOrchestrator", "import AgentLoop"]

        for url in apiFiles {
            let imports = allImports(in: url)
            for banned in bannedImports {
                XCTAssertFalse(
                    imports.contains(banned),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (API) must not import '\(banned)'"
                )
            }
        }
    }

    /// Memory module must not import Execution actions.
    func test_memory_does_not_import_execution() {
        let memoryFiles = swiftFiles(under: "Sources/OracleOS/Memory")
        let bannedImports = ["import VerifiedExecutor"]

        for url in memoryFiles {
            let imports = allImports(in: url)
            for banned in bannedImports {
                XCTAssertFalse(
                    imports.contains(banned),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (memory) must not import '\(banned)'"
                )
            }
        }
    }
}
