import Foundation
import Testing
@testable import OracleOS

@Suite("Code Intelligence Boundary")
struct CodeIntelligenceBoundaryTests {

    // MARK: - Phase 8: ProgramKnowledgeGraph is canonical

    @Test("ProgramKnowledgeGraph.swift exists and declares canonical model")
    func programKnowledgeGraphIsCanonical() throws {
        let file = sourcesRoot()
            .appendingPathComponent("Code")
            .appendingPathComponent("Intelligence")
            .appendingPathComponent("ProgramKnowledgeGraph.swift")
        #expect(
            FileManager.default.fileExists(atPath: file.path),
            "ProgramKnowledgeGraph.swift must exist"
        )
        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(
            content.contains("canonical"),
            "ProgramKnowledgeGraph.swift must declare itself as the canonical code model"
        )
    }

    @Test("Planning files do not directly instantiate raw code-intelligence graphs")
    func plannerUsesGraphQueriesNotRawGraphs() throws {
        let planningDir = sourcesRoot().appendingPathComponent("Planning")
        let files = try swiftFilesRecursive(in: planningDir)

        let forbidden = [
            "CallGraph(", "SymbolGraph(", "TestGraph(",
            "BuildGraph(", "DependencyGraph(",
        ]

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            for pattern in forbidden {
                #expect(
                    !content.contains(pattern),
                    "Planning file \(filename) must not directly instantiate \(pattern) — use ProgramKnowledgeGraph"
                )
            }
        }
    }

    // MARK: - Phase 9: RepairPipeline invariants

    @Test("Repair pipeline requires localization before patching")
    func repairPipelineRequiresLocalizationBeforePatching() {
        // Valid: localization comes before patchCandidates
        let valid: [RepairPipeline.Stage] = [.failure, .localization, .candidateSymbols, .patchCandidates]
        #expect(RepairPipeline.localizationPrecedesPatching(valid))

        // Invalid: patchCandidates without localization
        let invalid: [RepairPipeline.Stage] = [.failure, .patchCandidates]
        #expect(!RepairPipeline.localizationPrecedesPatching(invalid))

        // Valid: neither localization nor patching present
        let empty: [RepairPipeline.Stage] = [.failure]
        #expect(RepairPipeline.localizationPrecedesPatching(empty))
    }

    @Test("Repair pipeline requires sandbox validation before apply")
    func repairPipelineRequiresSandboxBeforeApply() {
        // Valid: sandbox before apply
        let valid: [RepairPipeline.Stage] = [.sandboxValidation, .regressionCheck, .rankFix, .apply]
        #expect(RepairPipeline.sandboxPrecedesApply(valid))

        // Invalid: apply without sandbox
        let invalid: [RepairPipeline.Stage] = [.failure, .apply]
        #expect(!RepairPipeline.sandboxPrecedesApply(invalid))

        // Valid: neither sandbox nor apply present
        let partial: [RepairPipeline.Stage] = [.failure, .localization]
        #expect(RepairPipeline.sandboxPrecedesApply(partial))
    }

    // MARK: - Helpers

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

}
