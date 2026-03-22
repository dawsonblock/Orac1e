import Foundation

final class ToolRouter {
    private let registry: ToolRegistry
    private let policy: ToolPolicy

    init(registry: ToolRegistry, policy: ToolPolicy) {
        self.registry = registry
        self.policy = policy
    }

    func selectTool(for capability: String, preferredToolID: String? = nil) -> ToolManifest? {
        if let preferredToolID,
           let manifest = registry.manifest(for: preferredToolID),
           policy.evaluate(manifest: manifest, capability: capability).allowed {
            return manifest
        }

        let allowed = registry.tools(for: capability)
            .filter { policy.evaluate(manifest: $0, capability: capability).allowed }

        return allowed.sorted { $0.id < $1.id }.first
    }
}
