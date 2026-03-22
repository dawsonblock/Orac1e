import Foundation

public struct IndexDiagnostics: Codable, Sendable, Equatable {
    public let fileCount: Int
    public let symbolCount: Int
    public let dependencyCount: Int
    public let callEdgeCount: Int
    public let testEdgeCount: Int
    public let buildTargetCount: Int
    public let persistedIndexPath: String?
    public let indexedAt: Date

    public init(
        fileCount: Int = 0,
        symbolCount: Int = 0,
        dependencyCount: Int = 0,
        callEdgeCount: Int = 0,
        testEdgeCount: Int = 0,
        buildTargetCount: Int = 0,
        persistedIndexPath: String? = nil,
        indexedAt: Date = Date()
    ) {
        self.fileCount = fileCount
        self.symbolCount = symbolCount
        self.dependencyCount = dependencyCount
        self.callEdgeCount = callEdgeCount
        self.testEdgeCount = testEdgeCount
        self.buildTargetCount = buildTargetCount
        self.persistedIndexPath = persistedIndexPath
        self.indexedAt = indexedAt
    }
}
