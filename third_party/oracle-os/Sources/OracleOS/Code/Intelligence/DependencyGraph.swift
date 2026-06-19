import Foundation

public enum DependencyType: String, Codable, Sendable, CaseIterable {
    case importDependency = "import"
    case include
    case packageDependency = "package-dependency"
    case buildDependency = "build-dependency"
}

public struct DependencyEdge: Codable, Sendable, Equatable {
    public let sourcePath: String
    public let dependency: String
    public let toFile: String?
    public let type: DependencyType

    public init(
        sourcePath: String,
        dependency: String,
        toFile: String? = nil,
        type: DependencyType = .importDependency
    ) {
        self.sourcePath = sourcePath
        self.dependency = dependency
        self.toFile = toFile
        self.type = type
    }
}

public struct DependencyGraph: Codable, Sendable, Equatable {
    public let edges: [DependencyEdge]

    public init(edges: [DependencyEdge] = []) {
        self.edges = edges
    }

    public func reverseDependencies(of path: String) -> [String] {
        edges.compactMap { edge in
            if edge.toFile == path || edge.dependency == path {
                return edge.sourcePath
            }
            return nil
        }.uniqued()
    }

    public func directDependencies(of path: String) -> [String] {
        edges.filter { $0.sourcePath == path }
            .map { $0.toFile ?? $0.dependency }
            .uniqued()
    }

    public func references(to path: String) -> [DependencyEdge] {
        edges.filter { edge in
            edge.toFile == path || edge.dependency == path
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
