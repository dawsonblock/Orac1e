import Foundation

public struct RepositoryTest: Codable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let symbolID: String?

    public init(name: String, path: String, symbolID: String? = nil) {
        self.name = name
        self.path = path
        self.symbolID = symbolID
    }
}

public struct TestEdge: Codable, Sendable, Equatable, Hashable {
    public let testSymbolID: String
    public let targetSymbolID: String

    public init(testSymbolID: String, targetSymbolID: String) {
        self.testSymbolID = testSymbolID
        self.targetSymbolID = targetSymbolID
    }
}

public struct TestGraph: Codable, Sendable, Equatable {
    public let tests: [RepositoryTest]
    public let edges: [TestEdge]

    public init(
        tests: [RepositoryTest] = [],
        edges: [TestEdge] = []
    ) {
        self.tests = tests
        self.edges = edges
    }

    public func testsCovering(symbolID: String) -> [RepositoryTest] {
        let testIDs = Set(edges.filter { $0.targetSymbolID == symbolID }.map(\.testSymbolID))
        return tests.filter { test in
            guard let symbolID = test.symbolID else { return false }
            return testIDs.contains(symbolID)
        }
    }

    public func testsCovering(path: String) -> [RepositoryTest] {
        tests.filter { $0.path == path || $0.path.localizedCaseInsensitiveContains(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) }
    }

    public func targetSymbolIDs(for testSymbolID: String) -> [String] {
        edges
            .filter { $0.testSymbolID == testSymbolID }
            .map(\.targetSymbolID)
    }
}
