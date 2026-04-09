import Foundation

public struct SandboxCleanupOutcome: Codable, Sendable, Equatable {
    public let removedWorktree: Bool
    public let removedBranch: Bool
    public let errors: [String]

    public init(removedWorktree: Bool, removedBranch: Bool, errors: [String] = []) {
        self.removedWorktree = removedWorktree
        self.removedBranch = removedBranch
        self.errors = errors
    }

    public var succeeded: Bool {
        errors.isEmpty && removedWorktree && removedBranch
    }
}

public struct ExperimentExecutedCommand: Codable, Sendable, Equatable {
    public let category: String
    public let executable: String
    public let arguments: [String]
    public let workspaceRoot: String
    public let summary: String

    public init(category: String, executable: String, arguments: [String], workspaceRoot: String, summary: String) {
        self.category = category
        self.executable = executable
        self.arguments = arguments
        self.workspaceRoot = workspaceRoot
        self.summary = summary
    }
}

public struct ExperimentIsolationMetadata: Codable, Sendable, Equatable {
    public let executionContext: String
    public let canonicalWorkspaceRoot: String
    public let sandboxRoot: String
    public let resolvedSandboxRoot: String
    public let candidatePaths: [String]
    public let executedCommands: [ExperimentExecutedCommand]
    public let commitCoordinatorMutationAllowed: Bool
    public let approvalPromotionAllowed: Bool
    public let liveRuntimeMutationAllowed: Bool
    public let cleanupOutcome: SandboxCleanupOutcome

    public init(
        executionContext: String = "sandboxed-experiment",
        canonicalWorkspaceRoot: String,
        sandboxRoot: String,
        resolvedSandboxRoot: String,
        candidatePaths: [String],
        executedCommands: [ExperimentExecutedCommand],
        commitCoordinatorMutationAllowed: Bool = false,
        approvalPromotionAllowed: Bool = false,
        liveRuntimeMutationAllowed: Bool = false,
        cleanupOutcome: SandboxCleanupOutcome
    ) {
        self.executionContext = executionContext
        self.canonicalWorkspaceRoot = canonicalWorkspaceRoot
        self.sandboxRoot = sandboxRoot
        self.resolvedSandboxRoot = resolvedSandboxRoot
        self.candidatePaths = candidatePaths
        self.executedCommands = executedCommands
        self.commitCoordinatorMutationAllowed = commitCoordinatorMutationAllowed
        self.approvalPromotionAllowed = approvalPromotionAllowed
        self.liveRuntimeMutationAllowed = liveRuntimeMutationAllowed
        self.cleanupOutcome = cleanupOutcome
    }
}

public struct ExperimentResult: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let experimentID: String
    public let candidate: CandidatePatch
    public let sandboxPath: String
    public let commandResults: [CommandResult]
    public let diffSummary: String
    public let architectureRiskScore: Double
    public let architectureFindings: [ArchitectureFinding]
    public let refactorProposalID: String?
    public let selected: Bool
    public let promptDiagnostics: PromptDiagnostics?
    public let isolationMetadata: ExperimentIsolationMetadata?

    public init(
        id: String = UUID().uuidString,
        experimentID: String,
        candidate: CandidatePatch,
        sandboxPath: String,
        commandResults: [CommandResult],
        diffSummary: String,
        architectureRiskScore: Double,
        architectureFindings: [ArchitectureFinding] = [],
        refactorProposalID: String? = nil,
        selected: Bool = false,
        promptDiagnostics: PromptDiagnostics? = nil,
        isolationMetadata: ExperimentIsolationMetadata? = nil
    ) {
        self.id = id
        self.experimentID = experimentID
        self.candidate = candidate
        self.sandboxPath = sandboxPath
        self.commandResults = commandResults
        self.diffSummary = diffSummary
        self.architectureRiskScore = architectureRiskScore
        self.architectureFindings = architectureFindings
        self.refactorProposalID = refactorProposalID
        self.selected = selected
        self.promptDiagnostics = promptDiagnostics
        self.isolationMetadata = isolationMetadata
    }

    public var succeeded: Bool {
        commandResults.allSatisfy(\.succeeded)
    }

    public var elapsedMs: Double {
        commandResults.reduce(0) { $0 + $1.elapsedMs }
    }

    public func with(promptDiagnostics: PromptDiagnostics?) -> ExperimentResult {
        ExperimentResult(
            id: id,
            experimentID: experimentID,
            candidate: candidate,
            sandboxPath: sandboxPath,
            commandResults: commandResults,
            diffSummary: diffSummary,
            architectureRiskScore: architectureRiskScore,
            architectureFindings: architectureFindings,
            refactorProposalID: refactorProposalID,
            selected: selected,
            promptDiagnostics: promptDiagnostics,
            isolationMetadata: isolationMetadata
        )
    }
}
