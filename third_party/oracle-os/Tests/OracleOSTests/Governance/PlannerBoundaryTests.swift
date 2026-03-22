import Foundation
import Testing
@testable import OracleOS

@Suite("Planner Boundary")
struct PlannerBoundaryTests {

    @Test("Planner does not resolve exact UI targets")
    func plannerDoesNotResolveUITargets() throws {
        let content = try plannerContents()
        #expect(!content.contains("BrowserTargetResolver.resolve"), "Planner should not resolve browser targets directly")
        #expect(!content.contains("HostTargetResolver.resolve"), "Planner should not resolve host targets directly")
        #expect(!content.contains("ElementRanker.rank"), "Planner should not rank elements directly")
    }

    @Test("Planner does not mutate files")
    func plannerDoesNotMutateFiles() throws {
        let content = try plannerContents()
        #expect(!content.contains("FileManager.default.createFile"), "Planner should not create files")
        #expect(!content.contains("write(to:"), "Planner should not write to files")
    }

    @Test("Planner does not execute commands directly")
    func plannerDoesNotExecuteCommands() throws {
        let content = try plannerContents()
        #expect(!content.contains("Process()"), "Planner should not spawn processes")
        #expect(!content.contains("executionDriver"), "Planner should not reference executionDriver")
    }

    @Test("Planner does not inline recovery mechanics")
    func plannerDoesNotInlineRecovery() throws {
        let content = try plannerContents()
        #expect(!content.contains("RecoveryStrategy"), "Planner should not reference RecoveryStrategy protocol")
        #expect(!content.contains("DismissModalStrategy"), "Planner should not reference specific recovery strategies")
        #expect(!content.contains("RefocusAppStrategy"), "Planner should not reference specific recovery strategies")
    }

    private func plannerContents() throws -> String {
        let plannerURL = repositoryRoot().appendingPathComponent(
            "Sources/OracleOS/Planning/MainPlanner.swift",
            isDirectory: false
        )
        return try String(contentsOf: plannerURL)
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while true {
            let packageManifestURL = url.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageManifestURL.path) {
                return url
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return url
            }

            url = parent
        }
    }
}
