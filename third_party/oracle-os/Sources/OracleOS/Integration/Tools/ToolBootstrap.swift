import Foundation

public struct CodingToolRegistrySummary: Codable, Sendable {
    public let rootPath: String
    public let toolIDs: [String]
    public let capabilities: [String]

    public var count: Int { toolIDs.count }

    public init(rootPath: String, toolIDs: [String], capabilities: [String]) {
        self.rootPath = rootPath
        self.toolIDs = toolIDs
        self.capabilities = capabilities
    }
}

public enum CodingToolBootstrap {
    public static func resolveToolsRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        if let explicit = environment["ORACLE_TOOL_MANIFESTS"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            let url = URL(fileURLWithPath: explicit)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        let candidates = candidateRoots(startingAt: currentDirectory)
        let fileManager = FileManager.default
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    public static func loadSummary(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> CodingToolRegistrySummary? {
        guard let root = resolveToolsRoot(environment: environment, currentDirectory: currentDirectory) else {
            return nil
        }

        let registry = ToolRegistry()
        try registry.load(from: root)
        let manifests = registry.all().sorted { $0.id < $1.id }
        let capabilities = Array(Set(manifests.flatMap(\.capabilities))).sorted()
        return CodingToolRegistrySummary(
            rootPath: root.path,
            toolIDs: manifests.map(\.id),
            capabilities: capabilities
        )
    }

    static func candidateRoots(startingAt currentDirectory: URL) -> [URL] {
        var urls: [URL] = []
        var current = currentDirectory.standardizedFileURL
        for _ in 0..<8 {
            urls.append(current.appendingPathComponent("integration/tools", isDirectory: true))
            current.deleteLastPathComponent()
        }
        return urls
    }
}
