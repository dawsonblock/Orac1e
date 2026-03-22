import Foundation
import Testing
@testable import OracleOS

@Suite("Execution Spine")
struct ExecutionSpineTests {
    @Test("Legacy bypass surfaces are removed")
    func legacyBypassSurfacesAreRemoved() throws {
        let sources = repositoryRoot().appendingPathComponent("Sources/OracleOS", isDirectory: true)
        let forbidden = ["ToolDispatcher", "CodeActionGateway", "performAction("]
        let offenders = try swiftFilesRecursive(in: sources).filter { file in
            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                return false
            }
            return forbidden.contains { content.contains($0) }
        }

        #expect(
            offenders.isEmpty,
            "Legacy execution bypass surfaces remain in source: \(offenders.map(\.path))"
        )
    }

    @Test("AgentLoop is a thin submitIntent wrapper")
    func agentLoopIsThin() throws {
        let loopDir = repositoryRoot()
            .appendingPathComponent("Sources/OracleOS/Execution/Loop", isDirectory: true)
        let loopFiles = try swiftFilesRecursive(in: loopDir)

        for file in loopFiles {
            guard file.lastPathComponent.hasPrefix("AgentLoop") else { continue }
            let content = try String(contentsOf: file, encoding: .utf8)
            #expect(!content.contains("decisionCoordinator."), "\(file.lastPathComponent) should not decide directly")
            #expect(!content.contains("executionCoordinator."), "\(file.lastPathComponent) should not execute directly")
            #expect(!content.contains("recoveryCoordinator."), "\(file.lastPathComponent) should not perform recovery directly")
            #expect(!content.contains("learningCoordinator."), "\(file.lastPathComponent) should not update learning directly")
            #expect(!content.contains("worldModel.reset("), "\(file.lastPathComponent) should not mutate world state")
        }
    }

    @Test("RuntimeOrchestrator uses committed state for planning")
    func runtimeOrchestratorPlansFromCommittedState() throws {
        let orchestratorPath = sourcesRoot()
            .appendingPathComponent("Runtime")
            .appendingPathComponent("RuntimeOrchestrator.swift")
        let content = try String(contentsOf: orchestratorPath, encoding: .utf8)

        #expect(
            content.contains("WorldStateModel(snapshot: await commitCoordinator.snapshot())"),
            "RuntimeOrchestrator should plan from committed state rather than a fresh empty model"
        )
        #expect(
            !content.contains("_legacyContext"),
            "RuntimeOrchestrator should not retain deprecated legacy context storage"
        )
    }

    @Test("Build and test commands still use /usr/bin/env")
    func buildTestCommandsUseEnv() throws {
        let plannerPath = sourcesRoot()
            .appendingPathComponent("Planning")
            .appendingPathComponent("MainPlanner+Planner.swift")
        let plannerContent = try String(contentsOf: plannerPath, encoding: .utf8)

        #expect(
            plannerContent.contains("executable: \"/usr/bin/env\""),
            "MainPlanner should construct build/test commands with /usr/bin/env"
        )
    }

    private func sourcesRoot() -> URL {
        repositoryRoot().appendingPathComponent("Sources/OracleOS", isDirectory: true)
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

    private func swiftFilesRecursive(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                result.append(fileURL)
            }
        }
        return result
    }
}
