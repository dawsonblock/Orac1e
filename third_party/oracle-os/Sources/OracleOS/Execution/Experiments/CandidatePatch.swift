import Foundation

public struct CandidatePatch: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let workspaceRelativePath: String
    public let content: String
    public let hypothesis: String?
    public let strategyKind: String?
    public let faultLocationConfidence: Double?
    public let complexity: Double?

    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String,
        workspaceRelativePath: String,
        content: String,
        hypothesis: String? = nil,
        strategyKind: String? = nil,
        faultLocationConfidence: Double? = nil,
        complexity: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.workspaceRelativePath = workspaceRelativePath
        self.content = content
        self.hypothesis = hypothesis
        self.strategyKind = strategyKind
        self.faultLocationConfidence = faultLocationConfidence
        self.complexity = complexity
    }
}
