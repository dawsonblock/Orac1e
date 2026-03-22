import Foundation

public struct ReasoningPlanningState: Sendable, Hashable {
    public var agentKind: AgentKind
    public var goalDescription: String
    public var planningStateID: PlanningStateID
    public var activeApplication: String?
    public var targetApplication: String?
    public var currentDomain: String?
    public var targetDomain: String?
    public var visibleTargets: [String]
    public var repoOpen: Bool
    public var repoDirty: Bool
    public var buildSucceeded: Bool?
    public var failingTests: Int?
    public var testsObserved: Bool
    public var patchApplied: Bool
    public var modalPresent: Bool
    public var preferredWorkspacePath: String?
    public var candidateWorkspacePaths: [String]
    public var workspaceRoot: String?
    public var riskPenalty: Double

    public init(
        taskContext: TaskContext,
        worldState: WorldState,
        memoryInfluence: MemoryInfluence
    ) {
        let loweredGoal = taskContext.goal.description.lowercased()
        let snapshot = worldState.repositorySnapshot
        let visibleTargets = Array(
            Set(
                worldState.observation.elements
                    .compactMap(\.label)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()

        let testsObserved = loweredGoal.contains("test")
            || loweredGoal.contains("failing")
            || worldState.lastAction?.action == "run_tests"
            || worldState.lastAction?.action == "test"
        let buildSucceeded: Bool?
        if loweredGoal.contains("build") || loweredGoal.contains("compile") {
            buildSucceeded = !loweredGoal.contains("fail")
        } else {
            buildSucceeded = nil
        }

        self.agentKind = taskContext.agentKind
        self.goalDescription = taskContext.goal.description
        self.planningStateID = worldState.planningState.id
        self.activeApplication = worldState.observation.app
        self.targetApplication = taskContext.goal.targetApp
        self.currentDomain = worldState.planningState.domain
        self.targetDomain = taskContext.goal.targetDomain
        self.visibleTargets = visibleTargets
        self.repoOpen = snapshot != nil || taskContext.workspaceRoot != nil
        self.repoDirty = snapshot?.isGitDirty ?? false
        self.buildSucceeded = buildSucceeded
        self.failingTests = testsObserved ? max(snapshot?.testGraph.tests.count ?? 0, 1) : nil
        self.testsObserved = testsObserved
        self.patchApplied = Self.patchApplied(lastAction: worldState.lastAction)
        self.modalPresent = Self.modalPresent(worldState: worldState)
        self.preferredWorkspacePath = memoryInfluence.preferredFixPath
        self.candidateWorkspacePaths = Self.candidateWorkspacePaths(
            goalDescription: loweredGoal,
            snapshot: snapshot,
            preferredPath: memoryInfluence.preferredFixPath
        )
        self.workspaceRoot = taskContext.workspaceRoot
        self.riskPenalty = memoryInfluence.riskPenalty
    }

    private static func patchApplied(lastAction: ActionIntent?) -> Bool {
        guard let lastAction else { return false }
        switch lastAction.action {
        case "edit_file", "edit-file", "generate_patch", "generate-patch", "write_file", "write-file":
            return true
        default:
            return false
        }
    }

    private static func modalPresent(worldState: WorldState) -> Bool {
        if worldState.planningState.modalClass != nil {
            return true
        }

        return worldState.observation.elements.contains { element in
            guard let role = element.role?.lowercased() else {
                return false
            }
            return role.contains("dialog")
                || role.contains("sheet")
                || role.contains("alert")
                || role.contains("popover")
        }
    }

    private static func candidateWorkspacePaths(
        goalDescription: String,
        snapshot: RepositorySnapshot?,
        preferredPath: String?
    ) -> [String] {
        guard let snapshot else {
            return preferredPath.map { [$0] } ?? []
        }

        var paths: [String] = []
        if let preferredPath {
            paths.append(preferredPath)
        }

        let goalTokens = Set(
            goalDescription
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "_" && $0 != "/" })
                .map(String.init)
                .map { $0.lowercased() }
                .filter { $0.count >= 3 }
        )

        let matching = snapshot.files
            .filter { !$0.isDirectory }
            .map(\.path)
            .filter { path in
                let loweredPath = path.lowercased()
                let basename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
                return goalTokens.contains(where: { loweredPath.contains($0) || basename.contains($0) })
            }

        paths.append(contentsOf: matching)
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
