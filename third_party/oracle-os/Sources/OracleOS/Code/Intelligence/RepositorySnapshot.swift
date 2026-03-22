import Foundation

public struct RepositoryFile: Codable, Sendable, Equatable {
    public let path: String
    public let isDirectory: Bool
    public let lastModifiedAt: Date?

    public init(path: String, isDirectory: Bool, lastModifiedAt: Date? = nil) {
        self.path = path
        self.isDirectory = isDirectory
        self.lastModifiedAt = lastModifiedAt
    }
}

public struct RepositorySnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let workspaceRoot: String
    public let buildTool: BuildTool
    public let files: [RepositoryFile]
    public let symbolGraph: SymbolGraph
    public let dependencyGraph: DependencyGraph
    public let callGraph: CallGraph
    public let testGraph: TestGraph
    public let buildGraph: BuildGraph
    public let activeBranch: String?
    public let isGitDirty: Bool
    public let indexDiagnostics: IndexDiagnostics
    public let indexedAt: Date

    public init(
        id: String,
        workspaceRoot: String,
        buildTool: BuildTool,
        files: [RepositoryFile],
        symbolGraph: SymbolGraph,
        dependencyGraph: DependencyGraph,
        callGraph: CallGraph = CallGraph(),
        testGraph: TestGraph,
        buildGraph: BuildGraph = BuildGraph(),
        activeBranch: String?,
        isGitDirty: Bool,
        indexDiagnostics: IndexDiagnostics = IndexDiagnostics(),
        indexedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceRoot = workspaceRoot
        self.buildTool = buildTool
        self.files = files
        self.symbolGraph = symbolGraph
        self.dependencyGraph = dependencyGraph
        self.callGraph = callGraph
        self.testGraph = testGraph
        self.buildGraph = buildGraph
        self.activeBranch = activeBranch
        self.isGitDirty = isGitDirty
        self.indexDiagnostics = indexDiagnostics
        self.indexedAt = indexedAt
    }
}
