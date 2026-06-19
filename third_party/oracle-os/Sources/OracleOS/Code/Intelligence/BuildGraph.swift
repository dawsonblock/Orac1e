import Foundation

public struct BuildTarget: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let sourceFiles: [String]
    public let dependencies: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        sourceFiles: [String],
        dependencies: [String]
    ) {
        self.id = id
        self.name = name
        self.sourceFiles = sourceFiles
        self.dependencies = dependencies
    }
}

public struct BuildGraph: Codable, Sendable, Equatable {
    public let targets: [BuildTarget]

    public init(targets: [BuildTarget] = []) {
        self.targets = targets
    }

    public func targets(containing file: String) -> [BuildTarget] {
        targets.filter { $0.sourceFiles.contains(file) }
    }
}
