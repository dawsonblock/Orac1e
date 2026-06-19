import Foundation

public enum CodeCommandCategory: String, Codable, Sendable, CaseIterable {
    case indexRepository = "index-repository"
    case searchCode = "search-code"
    case openFile = "open-file"
    case editFile = "edit-file"
    case writeFile = "write-file"
    case generatePatch = "generate-patch"
    case build
    case test
    case formatter
    case linter
    case parseBuildFailure = "parse-build-failure"
    case parseTestFailure = "parse-test-failure"
    case gitStatus = "git-status"
    case gitBranch = "git-branch"
    case gitCommit = "git-commit"
    case gitPush = "git-push"

    public var isWrite: Bool {
        switch self {
        case .editFile, .writeFile, .generatePatch, .formatter, .gitBranch, .gitCommit, .gitPush:
            true
        default:
            false
        }
    }

    public var isGit: Bool {
        switch self {
        case .gitStatus, .gitBranch, .gitCommit, .gitPush:
            true
        default:
            false
        }
    }
}

public struct CommandSpec: Codable, Sendable, Equatable {
    public let category: CodeCommandCategory
    public let executable: String
    public let arguments: [String]
    public let workspaceRoot: String
    public let workspaceRelativePath: String?
    public let summary: String
    public let mutatesWorkspace: Bool
    public let touchesNetwork: Bool

    public init(
        category: CodeCommandCategory,
        executable: String,
        arguments: [String],
        workspaceRoot: String,
        workspaceRelativePath: String? = nil,
        summary: String,
        mutatesWorkspace: Bool? = nil,
        touchesNetwork: Bool = false
    ) {
        self.category = category
        self.executable = executable
        self.arguments = arguments
        self.workspaceRoot = workspaceRoot
        self.workspaceRelativePath = workspaceRelativePath
        self.summary = summary
        self.mutatesWorkspace = mutatesWorkspace ?? category.isWrite
        self.touchesNetwork = touchesNetwork
    }
}
