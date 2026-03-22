import Foundation

final class ToolRegistry: @unchecked Sendable {
    private(set) var manifests: [String: ToolManifest] = [:]

    func load(from directory: URL) throws {
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

    func manifest(for toolID: String) -> ToolManifest? {
        manifests[toolID]
    }

    func all() -> [ToolManifest] {
        Array(manifests.values)
    }

    func tools(for capability: String) -> [ToolManifest] {
        manifests.values.filter { $0.capabilities.contains(capability) }
    }

    func tools(of kind: ToolKind) -> [ToolManifest] {
        manifests.values.filter { $0.kind == kind }
    }
}
