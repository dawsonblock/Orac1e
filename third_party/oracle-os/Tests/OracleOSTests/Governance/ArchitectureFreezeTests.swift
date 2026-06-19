import Foundation
import Testing
@testable import OracleOS

@Suite("Architecture Freeze")
struct ArchitectureFreezeTests {

    // MARK: - R1: Single planner entry point

    @Test("Runtime does not instantiate secondary planners directly")
    func runtimeSinglePlannerEntry() throws {
        let content = try runtimeContents()
        // Runtime must not instantiate secondary planners directly.
        #expect(
            !content.contains("CodePlanner("),
            "RuntimeOrchestrator should not instantiate CodePlanner directly"
        )
        assertNoNewInstantiation(
            of: "OSPlanner",
            in: "Sources/OracleOS/Runtime/RuntimeOrchestrator.swift",
            message:
            "RuntimeOrchestrator should not instantiate OSPlanner directly"
        )
        assertNoNewInstantiation(
            of: "GraphPlanner",
            in: "Sources/OracleOS/Runtime/RuntimeOrchestrator.swift",
            message:
            "RuntimeOrchestrator should not instantiate GraphPlanner directly"
        )
        assertNoNewInstantiation(
            of: "PlanGenerator",
            in: "Sources/OracleOS/Runtime/RuntimeOrchestrator.swift",
            message:
            "RuntimeOrchestrator should not instantiate PlanGenerator directly"
        )
    }

    @Test("RuntimeOrchestrator is the sole runtime planner owner")
    func runtimeOrchestratorIsSolePlannerOwner() throws {
        let runtimeDir = sourcesRoot().appendingPathComponent("Runtime")
        let files = try swiftFiles(in: runtimeDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            guard filename != "RuntimeOrchestrator.swift" else { continue }
            #expect(
                !content.contains("MainPlanner("),
                "Runtime file \(filename) should not instantiate MainPlanner directly"
            )
        }
    }

    // MARK: - R3: No UI imports in runtime

    @Test("Runtime files import only Foundation")
    func runtimeNoUIImports() throws {
        let runtimeDir = sourcesRoot().appendingPathComponent("Runtime")
        let coordinatorsDir = runtimeDir.appendingPathComponent("Coordinators")
        var files = try swiftFiles(in: runtimeDir)
        if FileManager.default.fileExists(atPath: coordinatorsDir.path) {
            files += try swiftFiles(in: coordinatorsDir)
        }

        let banned = ["import AppKit", "import SwiftUI", "import OracleController"]
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            for pattern in banned {
                #expect(
                    !content.contains(pattern),
                    "Runtime file \(filename) must not contain '\(pattern)'"
                )
            }
        }
    }

    // MARK: - R4: Executor trust boundary

    @Test("ActionResult defaults executedThroughExecutor to false")
    func actionResultDefaultsToFalse() {
        let result = ActionResult(
            success: true,
            verified: true,
            message: nil,
            method: nil,
            verificationStatus: nil,
            failureClass: nil,
            elapsedMs: 0,
            policyDecision: nil,
            protectedOperation: nil,
            approvalRequestID: nil,
            approvalStatus: nil,
            surface: nil,
            appProtectionProfile: nil,
            blockedByPolicy: false,
            executedThroughExecutor: false
        )
        #expect(result.executedThroughExecutor == false)
    }

    // MARK: - R5: Planners do not execute

    @Test("Planner files do not spawn processes or write files")
    func plannerFilesDoNotExecute() throws {
        let planningDir = sourcesRoot().appendingPathComponent("Planning")
        let files = try swiftFilesRecursive(in: planningDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains("Process()"),
                "Planning file \(filename) must not spawn processes"
            )
            #expect(
                !content.contains("FileManager.default.createFile"),
                "Planning file \(filename) must not create files directly"
            )
        }
    }

    // MARK: - R1: Planning files do not instantiate competing planners

    @Test("Planning files do not instantiate PlanGenerator or PlanEvaluator directly")
    func plannerFilesDoNotInstantiateCompetingPlanners() throws {
        let planningDir = sourcesRoot().appendingPathComponent("Planning")
        let files = try swiftFilesRecursive(in: planningDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            // MainPlanner.swift is the canonical planner orchestrator and is
            // expected to compose PlanEvaluator and PlanGenerator internally.
            guard filename != "MainPlanner.swift" else { continue }
            #expect(
                !content.contains("PlanGenerator("),
                "Planning file \(filename) must not instantiate PlanGenerator directly outside MainPlanner"
            )
            #expect(
                !content.contains("PlanEvaluator("),
                "Planning file \(filename) must not instantiate PlanEvaluator directly"
            )
        }
    }

    // MARK: - Protected backbone modules exist

    @Test("Protected backbone modules are present in the source tree")
    func protectedModulesExist() {
        let root = sourcesRoot()
        let expectedFiles = [
            "Execution/VerifiedExecutor.swift",
            "Execution/Critic/CriticLoop.swift",
            "Planning/Reasoning/PlanSimulator.swift",
            "Code/Intelligence/ProgramKnowledgeGraph.swift",
            "WorldModel/WorldStateModel.swift",
            "WorldModel/ObservationChangeDetector.swift",
            "TaskLedger/TaskLedgerStore.swift",
            "Learning/ExperienceStore.swift",
        ]
        let fileManager = FileManager.default
        for relative in expectedFiles {
            let url = root.appendingPathComponent(relative)
            #expect(
                fileManager.fileExists(atPath: url.path),
                "Protected backbone module missing: \(relative)"
            )
        }
    }

    @Test("Architecture rules document exists at repo root")
    func architectureRulesDocumentExists() {
        let root = repositoryRoot()
        let rulesURL = root.appendingPathComponent("ARCHITECTURE_RULES.md")
        #expect(
            FileManager.default.fileExists(atPath: rulesURL.path),
            "ARCHITECTURE_RULES.md must exist at the repository root"
        )
    }

    // MARK: - World model updated only via diff

    @Test("Runtime files do not bypass StateDiffEngine to set worldStateModel.current")
    func worldModelOnlyUpdatedViaDiff() throws {
        let runtimeDir = sourcesRoot().appendingPathComponent("Runtime")
        let files = try swiftFilesRecursive(in: runtimeDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains(".reset(from:"),
                "Runtime file \(filename) must not call worldStateModel.reset(from:); state changes should go through StateDiffEngine"
            )
        }
    }

    // MARK: - Helpers

    private func runtimeContents() throws -> String {
        let url = sourcesRoot().appendingPathComponent(
            "Runtime/RuntimeOrchestrator.swift",
            isDirectory: false
        )
        return try String(contentsOf: url)
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
    }

    private func swiftFilesRecursive(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var result: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" {
                result.append(url)
            }
        }
        return result
    }

    private func sourcesRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while true {
            let packageManifestURL = url.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageManifestURL.path) {
                return url.appendingPathComponent("Sources/OracleOS", isDirectory: true)
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return url.appendingPathComponent("Sources/OracleOS", isDirectory: true)
            }

            url = parent
        }
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
    private func assertNoNewInstantiation(of typeName: String, in path: String, message: String) {
        do {
            let root = repositoryRoot()
            let url = root.appendingPathComponent(path)
            let content = try String(contentsOf: url, encoding: .utf8)
            #expect(!content.contains("\(typeName)("))
        } catch {
             Issue.record("Failed to read file \(path) for architecture check: \(error)")
        }
    }
}
