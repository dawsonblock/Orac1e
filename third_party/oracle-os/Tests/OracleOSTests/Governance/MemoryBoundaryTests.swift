import Foundation
import Testing
@testable import OracleOS

@Suite("Memory Boundary")
struct MemoryBoundaryTests {

    // MARK: - Runtime files do not directly instantiate ProjectMemoryStore

    @Test("Runtime files do not directly instantiate ProjectMemoryStore")
    func runtimeDoesNotInstantiateProjectMemoryStore() throws {
        let runtimeDir = sourcesRoot().appendingPathComponent("Runtime")
        let files = try swiftFilesRecursive(in: runtimeDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains("ProjectMemoryStore("),
                "Runtime file \(filename) must not instantiate ProjectMemoryStore directly"
            )
        }
    }

    // MARK: - Runtime files do not directly instantiate raw memory stores

    @Test("Runtime files do not directly instantiate raw memory stores")
    func runtimeDoesNotInstantiateRawMemoryStores() throws {
        let runtimeDir = sourcesRoot().appendingPathComponent("Runtime")
        let files = try swiftFilesRecursive(in: runtimeDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains("PatternMemoryStore("),
                "Runtime file \(filename) must not instantiate PatternMemoryStore directly; use MemoryRouter"
            )
            #expect(
                !content.contains("ExecutionMemoryStore("),
                "Runtime file \(filename) must not instantiate ExecutionMemoryStore directly; use MemoryRouter"
            )
        }
    }

    // MARK: - Planner files do not write to memory stores

    @Test("Planner files do not directly write to memory stores")
    func plannerFilesDoNotWriteToMemory() throws {
        let planningDir = sourcesRoot()
            .appendingPathComponent("Agent")
            .appendingPathComponent("Planning")
        let files = try swiftFilesRecursive(in: planningDir)

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains(".record("),
                "Planning file \(filename) must not call .record() on memory stores"
            )
        }
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
