import Foundation

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
        promptDiagnostics: PromptDiagnostics? = nil
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
            promptDiagnostics: promptDiagnostics
        )
    }
}
