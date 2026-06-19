import Foundation

public enum SymbolKind: String, Codable, Sendable, CaseIterable {
    case function
    case method
    case `class`
    case `struct`
    case interface
    case `enum`
    case module
    case constant
    case variable
}

public enum SymbolEdgeKind: String, Codable, Sendable, CaseIterable {
    case defines
    case declares
    case implements
    case inherits
}

public struct SymbolNode: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let kind: SymbolKind
    public let file: String
    public let lineStart: Int
    public let lineEnd: Int

    public init(
        id: String,
        name: String,
        kind: SymbolKind,
        file: String,
        lineStart: Int,
        lineEnd: Int
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.file = file
        self.lineStart = lineStart
        self.lineEnd = lineEnd
    }
}

public struct SymbolEdge: Codable, Sendable, Equatable, Hashable {
    public let fromSymbolID: String
    public let toSymbolID: String
    public let kind: SymbolEdgeKind

    public init(
        fromSymbolID: String,
        toSymbolID: String,
        kind: SymbolEdgeKind
    ) {
        self.fromSymbolID = fromSymbolID
        self.toSymbolID = toSymbolID
        self.kind = kind
    }
}

public struct RepositorySymbol: Codable, Sendable, Hashable {
    public let name: String
    public let kind: String
    public let path: String
    public let line: Int?

    public init(name: String, kind: String, path: String, line: Int? = nil) {
        self.name = name
        self.kind = kind
        self.path = path
        self.line = line
    }
}

public struct SymbolGraph: Codable, Sendable, Equatable {
    public let nodes: [SymbolNode]
    public let edges: [SymbolEdge]

    public init(
        nodes: [SymbolNode] = [],
        edges: [SymbolEdge] = []
    ) {
        self.nodes = nodes
        self.edges = edges
    }

    public init(symbols: [RepositorySymbol]) {
        self.nodes = symbols.enumerated().map { index, symbol in
            SymbolNode(
                id: "\(symbol.path)|\(symbol.name)|\(index)",
                name: symbol.name,
                kind: SymbolKind(rawValue: symbol.kind) ?? .function,
                file: symbol.path,
                lineStart: symbol.line ?? 1,
                lineEnd: symbol.line ?? 1
            )
        }
        self.edges = []
    }

    public var symbols: [RepositorySymbol] {
        nodes.map {
            RepositorySymbol(
                name: $0.name,
                kind: $0.kind.rawValue,
                path: $0.file,
                line: $0.lineStart
            )
        }
    }

    public func nodes(inFile path: String) -> [SymbolNode] {
        nodes.filter { $0.file == path }
    }

    public func node(id: String) -> SymbolNode? {
        nodes.first { $0.id == id }
    }

    public func nodes(named name: String) -> [SymbolNode] {
        let normalized = name.lowercased()
        return nodes.filter { $0.name.lowercased().contains(normalized) }
    }
}
