import Foundation

public struct CallEdge: Codable, Sendable, Equatable, Hashable {
    public let caller: String
    public let callee: String

    public init(caller: String, callee: String) {
        self.caller = caller
        self.callee = callee
    }
}

public struct CallGraph: Codable, Sendable, Equatable {
    public let edges: [CallEdge]

    public init(edges: [CallEdge] = []) {
        self.edges = edges
    }

    public func callers(of symbolID: String) -> [String] {
        edges.filter { $0.callee == symbolID }.map(\.caller).uniqued()
    }

    public func callees(of symbolID: String) -> [String] {
        edges.filter { $0.caller == symbolID }.map(\.callee).uniqued()
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
