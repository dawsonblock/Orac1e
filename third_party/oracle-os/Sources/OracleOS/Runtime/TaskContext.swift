import Foundation

public struct TaskContext: Sendable, Codable, Equatable {
    public let goal: Goal
    public let agentKind: AgentKind
    public let workspaceRoot: String?
    public let phases: [TaskStepPhase]
    public let projectMemoryRoot: String?
    public let experimentsRoot: String?
    public let maxExperimentCandidates: Int
    public let experimentCandidates: [CandidatePatch]

    public init(
        goal: Goal,
        agentKind: AgentKind,
        workspaceRoot: String? = nil,
        phases: [TaskStepPhase],
        projectMemoryRoot: String? = nil,
        experimentsRoot: String? = nil,
        maxExperimentCandidates: Int = 3,
        experimentCandidates: [CandidatePatch] = []
    ) {
        self.goal = goal
        self.agentKind = agentKind
        self.workspaceRoot = workspaceRoot
        self.phases = phases
        self.projectMemoryRoot = projectMemoryRoot
        self.experimentsRoot = experimentsRoot
        self.maxExperimentCandidates = maxExperimentCandidates
        self.experimentCandidates = experimentCandidates
    }

    public static func from(
        goal: Goal,
        workspaceRoot: URL? = nil
    ) -> TaskContext {
        let agentKind = GoalClassifier.classify(
            description: goal.description,
            workspaceRoot: workspaceRoot
        )
        let phases: [TaskStepPhase] = switch agentKind {
        case .os:
            [.operatingSystem]
        case .code:
            [.engineering]
        case .mixed:
            [.handoff, .engineering]
        }

        return TaskContext(
            goal: goal,
            agentKind: agentKind,
            workspaceRoot: workspaceRoot?.path,
            phases: phases,
            projectMemoryRoot: workspaceRoot?.appendingPathComponent("ProjectMemory", isDirectory: true).path,
            experimentsRoot: workspaceRoot?.appendingPathComponent(".oracle/experiments", isDirectory: true).path,
            maxExperimentCandidates: 3,
            experimentCandidates: Array((goal.experimentCandidates ?? []).prefix(3))
        )
    }
}
