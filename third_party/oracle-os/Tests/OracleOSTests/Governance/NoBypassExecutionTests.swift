import Foundation
import Testing
@testable import OracleOS

@Suite("No Bypass Execution")
struct NoBypassExecutionTests {

    @Test("Browser automation actions do not call executionDriver directly")
    func browserActionsUseExecutor() throws {
        let browserDir = sourcesRoot()
            .appendingPathComponent("Browser")
            .appendingPathComponent("Automation")
        let files = try FileManager.default.contentsOfDirectory(
            at: browserDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            guard filename != "BrowserController.swift" else { continue }
            #expect(
                !content.contains("executionDriver.execute"),
                "Browser automation file \(filename) should not call executionDriver.execute directly"
            )
        }
    }

    @Test("Host automation actions do not call executionDriver directly")
    func hostActionsUseExecutor() throws {
        let hostDir = sourcesRoot().appendingPathComponent("HostAutomation")
        let files = try FileManager.default.contentsOfDirectory(
            at: hostDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains("executionDriver.execute"),
                "Host automation file \(filename) should not call executionDriver.execute directly"
            )
        }
    }

    @Test("Recovery strategies do not call executionDriver directly")
    func recoveryStrategiesUseExecutor() throws {
        let strategiesDir = sourcesRoot()
            .appendingPathComponent("Recovery")
            .appendingPathComponent("Strategies")
        let files = try FileManager.default.contentsOfDirectory(
            at: strategiesDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains("executionDriver.execute"),
                "Recovery strategy \(filename) should not call executionDriver.execute directly"
            )
        }
    }

    @Test("Tool implementations do not call executionDriver directly")
    func toolsUseExecutor() throws {
        let toolsDir = sourcesRoot().appendingPathComponent("Tools")
        guard FileManager.default.fileExists(atPath: toolsDir.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(
            at: toolsDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let filename = file.lastPathComponent
            #expect(
                !content.contains("executionDriver.execute"),
                "Tool file \(filename) should not call executionDriver.execute directly"
            )
        }
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
