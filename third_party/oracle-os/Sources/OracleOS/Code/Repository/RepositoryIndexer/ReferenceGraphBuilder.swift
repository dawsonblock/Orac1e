import Foundation
public struct ReferenceGraphBuilder {
    public init() {}
    public func build(symbols: [ExtractedSymbol]) -> ReferenceGraph {
        ReferenceGraph(nodes: symbols.map { $0.name }, edges: [:])
    }
}
public struct ReferenceGraph: Sendable {
    public let nodes: [String]; public let edges: [String: [String]]
    public init(nodes: [String], edges: [String: [String]]) { self.nodes = nodes; self.edges = edges }
}
