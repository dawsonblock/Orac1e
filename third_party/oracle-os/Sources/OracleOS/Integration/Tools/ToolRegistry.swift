import Foundation

public final class ToolRegistry: @unchecked Sendable {
    public private(set) var manifests: [String: ToolManifest] = [:]

    public init() {}

    public func load(from directory: URL) throws {
        manifests.removeAll()

        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            let manifestURL = item.appendingPathComponent("tool.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            let manifest = try decoder.decode(ToolManifest.self, from: data)

            guard manifests[manifest.id] == nil else {
                throw NSError(
                    domain: "ToolRegistry",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Duplicate tool id: \(manifest.id)"]
                )
            }

            manifests[manifest.id] = manifest
        }
    }

    public func manifest(for toolID: String) -> ToolManifest? {
        manifests[toolID]
    }

    public func all() -> [ToolManifest] {
        Array(manifests.values)
    }

    public func tools(for capability: String) -> [ToolManifest] {
        manifests.values.filter { $0.capabilities.contains(capability) }
    }

    public func tools(of kind: ToolKind) -> [ToolManifest] {
        manifests.values.filter { $0.kind == kind }
    }
}
