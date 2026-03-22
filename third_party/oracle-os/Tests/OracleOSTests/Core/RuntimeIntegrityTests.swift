import Foundation
import Testing
@testable import OracleOS

@Suite("Runtime Integrity")
struct RuntimeIntegrityTests {
    @Test("Legacy runtime bypass symbols remain absent")
    func legacyBypassSymbolsRemainAbsent() throws {
        let sourcesRoot = repositoryRoot().appendingPathComponent("Sources/OracleOS", isDirectory: true)
        let forbidden = ["performAction(", "executeLegacy(", "VerifiedActionExecutor", "ToolDispatcher", "CodeActionGateway"]
        let offenders = try swiftFiles(in: sourcesRoot).filter { fileURL in
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return false
            }
            return forbidden.contains(where: contents.contains)
        }
        #expect(
            offenders.isEmpty,
            "Forbidden legacy runtime symbols found: \(offenders.map(\.path))"
        )
    }

    @Test("Legacy RuntimeContext shortcut is removed from orchestrator")
    func runtimeOrchestratorDoesNotExposeLegacyContext() throws {
        let root = repositoryRoot()
        let orchestratorURL = root.appendingPathComponent("Sources/OracleOS/Runtime/RuntimeOrchestrator.swift")
        let contents = try String(contentsOf: orchestratorURL, encoding: .utf8)

        #expect(
            !contents.contains("_legacyContext"),
            "RuntimeOrchestrator should not expose legacy context shortcuts"
        )
    }

    @Test("Diagnostics placeholder baseline metrics JSON is removed")
    func diagnosticsPlaceholderBaselineIsRemoved() {
        let path = repositoryRoot().appendingPathComponent("Diagnostics/baseline_metrics.json", isDirectory: false)
        #expect(
            FileManager.default.fileExists(atPath: path.path) == false,
            "Diagnostics/baseline_metrics.json should not exist; eval baselines are sourced from OracleOSEvals."
        )
    }

    @Test("Runtime invariant docs are present")
    func runtimeInvariantDocsExist() {
        let root = repositoryRoot()
        let requiredDocs = [
            "docs/runtime_invariants.md",
            "docs/migration_cleanup.md",
        ]
        for doc in requiredDocs {
            let url = root.appendingPathComponent(doc, isDirectory: false)
            #expect(FileManager.default.fileExists(atPath: url.path), "Missing required runtime invariant doc: \(doc)")
        }
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            files.append(url)
        }
        return files
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

    private func relativePath(of fileURL: URL, from root: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if fileURL.path.hasPrefix(prefix) {
            return String(fileURL.path.dropFirst(prefix.count))
        }
        return fileURL.path
    }
}
