import Foundation

public struct ExperimentSpec: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let goalDescription: String
    public let workspaceRoot: String
    public let candidates: [CandidatePatch]
    public let buildCommand: CommandSpec?
    public let testCommand: CommandSpec?
    public let promptDiagnostics: PromptDiagnostics?

    public init(
        id: String = UUID().uuidString,
        goalDescription: String,
        workspaceRoot: String,
        candidates: [CandidatePatch],
        buildCommand: CommandSpec? = nil,
        testCommand: CommandSpec? = nil,
        promptDiagnostics: PromptDiagnostics? = nil
    ) {
        self.id = id
        self.goalDescription = goalDescription
        self.workspaceRoot = workspaceRoot
        self.candidates = candidates
        self.buildCommand = buildCommand
        self.testCommand = testCommand
        self.promptDiagnostics = promptDiagnostics
    }

    /// Returns a copy with candidates truncated to `ExperimentLimits.maxCandidates`.
    public func boundedByLimits() -> ExperimentSpec {
        let bounded = Array(candidates.prefix(ExperimentLimits.maxCandidates))
        guard bounded.count != candidates.count else { return self }
        return ExperimentSpec(
            id: id,
            goalDescription: goalDescription,
            workspaceRoot: workspaceRoot,
            candidates: bounded,
            buildCommand: buildCommand,
            testCommand: testCommand,
            promptDiagnostics: promptDiagnostics
        )
    }
}
