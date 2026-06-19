import Foundation

public struct ArchitectureModuleGraph: Codable, Sendable, Equatable {
    public let modules: [String: Set<String>]

    public init(modules: [String: Set<String>] = [:]) {
        self.modules = modules
    }

    public static func moduleName(for path: String) -> String {
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 3 else {
            return components.first ?? path
        }

        if components[0] == "Sources", components[1] == "OracleOS" {
            let rest = Array(components.dropFirst(2))
            if rest.count >= 2, ["Agent", "Core", "Learning"].contains(rest[0]) {
                return "\(rest[0])/\(rest[1])"
            }
            if rest.count >= 3 {
                return "\(rest[0])/\(rest[1])"
            }
            return rest.first ?? "OracleOS"
        }

        if components[0] == "Tests", components.count >= 2 {
            return "\(components[0])/\(components[1])"
        }

        return components.prefix(2).joined(separator: "/")
    }

    public static func build(from snapshot: RepositorySnapshot) -> ArchitectureModuleGraph {
        var modules: [String: Set<String>] = [:]
        for file in snapshot.files where !file.isDirectory {
            let module = moduleName(for: file.path)
            if modules[module] == nil {
                modules[module] = []
            }
        }

        for edge in snapshot.dependencyGraph.edges {
            let sourceModule = moduleName(for: edge.sourcePath)
            let dependency = inferredModule(for: edge.dependency, snapshot: snapshot)
            if let dependency, dependency != sourceModule {
                modules[sourceModule, default: []].insert(dependency)
            }
        }

        return ArchitectureModuleGraph(modules: modules)
    }

    private static func inferredModule(for dependency: String, snapshot: RepositorySnapshot) -> String? {
        if snapshot.files.contains(where: { $0.path.contains(dependency) }) {
            return moduleName(for: dependency)
        }

        let candidates = Set(snapshot.files.compactMap { file -> String? in
            let module = moduleName(for: file.path)
            return module.localizedCaseInsensitiveContains(dependency) ? module : nil
        })
        return candidates.sorted().first
    }
}
