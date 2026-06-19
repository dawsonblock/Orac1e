import Foundation

public struct WorkflowParameter: Sendable, Equatable, Codable {
    public let name: String
    public let kind: WorkflowParameterKind
    public let exampleValues: [String]
    public let stepIndices: [Int]

    public init(
        name: String,
        kind: WorkflowParameterKind,
        exampleValues: [String] = [],
        stepIndices: [Int] = []
    ) {
        self.name = name
        self.kind = kind
        self.exampleValues = exampleValues
        self.stepIndices = stepIndices
    }
}

public enum WorkflowParameterKind: String, Sendable, Codable, CaseIterable {
    case repositoryName = "repository"
    case filePath = "file-path"
    case symbolName = "symbol"
    case url = "url"
    case browserElementGroup = "browser-element-group"
    case windowOrAppName = "ui-label"
    case branchName = "branch"
    case testName = "test-name"
    case text = "text"

    public static func infer(from kind: String) -> WorkflowParameterKind {
        WorkflowParameterKind(rawValue: kind) ?? .text
    }
}
