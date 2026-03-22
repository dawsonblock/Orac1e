import Foundation

public enum CodingWorkerKind: String, Codable, Sendable {
    case aider
    case codeAgentRuntimeHardened = "code-agent-runtime-hardened"
}

public struct CodingContextSnippet: Codable, Sendable {
    public let path: String
    public let snippet: String
    public let startLine: Int?
    public let endLine: Int?
    public let score: Double?

    enum CodingKeys: String, CodingKey {
        case path, snippet, score
        case startLine = "start_line"
        case endLine = "end_line"
    }

    public init(
        path: String,
        snippet: String,
        startLine: Int? = nil,
        endLine: Int? = nil,
        score: Double? = nil
    ) {
        self.path = path
        self.snippet = snippet
        self.startLine = startLine
        self.endLine = endLine
        self.score = score
    }
}

public struct CodingWorkerContext: Codable, Sendable {
    public let files: [String]
    public let snippets: [CodingContextSnippet]
    public let docs: [[String: String]]

    public init(
        files: [String] = [],
        snippets: [CodingContextSnippet] = [],
        docs: [[String: String]] = []
    ) {
        self.files = files
        self.snippets = snippets
        self.docs = docs
    }
}

public struct CodingWorkerConstraints: Codable, Sendable {
    public let allowedPaths: [String]
    public let maxFiles: Int
    public let maxChangedLines: Int
    public let allowShell: Bool

    enum CodingKeys: String, CodingKey {
        case allowedPaths = "allowed_paths"
        case maxFiles = "max_files"
        case maxChangedLines = "max_changed_lines"
        case allowShell = "allow_shell"
    }

    public init(
        allowedPaths: [String],
        maxFiles: Int = 6,
        maxChangedLines: Int = 300,
        allowShell: Bool = false
    ) {
        self.allowedPaths = allowedPaths
        self.maxFiles = maxFiles
        self.maxChangedLines = maxChangedLines
        self.allowShell = allowShell
    }
}

public struct CodingWorkerProposeRequest: Codable, Sendable {
    public let runID: String
    public let repoName: String
    public let repoPath: String
    public let task: String
    public let mode: CodingRunMode
    public let context: CodingWorkerContext
    public let constraints: CodingWorkerConstraints

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case repoName = "repo_name"
        case repoPath = "repo_path"
        case task, mode, context, constraints
    }

    public init(
        runID: String,
        repoName: String,
        repoPath: String,
        task: String,
        mode: CodingRunMode,
        context: CodingWorkerContext,
        constraints: CodingWorkerConstraints
    ) {
        self.runID = runID
        self.repoName = repoName
        self.repoPath = repoPath
        self.task = task
        self.mode = mode
        self.context = context
        self.constraints = constraints
    }
}

public struct CodingWorkerProposeResponse: Codable, Sendable {
    public let status: String
    public let worker: String
    public let summary: String
    public let diff: String
    public let touchedFiles: [String]
    public let commandsRequested: [String]
    public let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case status, worker, summary, diff, warnings
        case touchedFiles = "touched_files"
        case commandsRequested = "commands_requested"
    }
}
