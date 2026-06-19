import Foundation
@testable import OracleOS

// Legacy type aliases used by older tests.
typealias TaskNode = TaskRecord
typealias TaskEdge = TaskRecordEdge
typealias TaskGraph = TaskLedger
typealias TaskGraphStore = TaskLedgerStore
typealias PlanningGraphStore = GraphStore
typealias GraphScorer = LedgerScorer
typealias GraphNavigator = LedgerNavigator
typealias GraphMainPlanner = GraphPlanner
typealias TraceStore = ExperienceStore

extension AbstractTaskState {
    static var repo_loaded: Self { .repoLoaded }
    static var tests_running: Self { .testsRunning }
    static var tests_passed: Self { .testsPassed }
    static var build_failed: Self { .buildFailed }
    static var build_running: Self { .buildRunning }
    static var task_started: Self { .taskStarted }
    static var navigation_completed: Self { .navigationCompleted }
}

extension SelectedStrategy {
    static let testDefault = SelectedStrategy(
        kind: .graphNavigation,
        confidence: 1.0,
        rationale: "test default strategy",
        allowedOperatorFamilies: OperatorFamily.allCases,
        reevaluateAfterStepCount: 5
    )
}

extension MainPlanner {
    func nextStep(
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore = UnifiedMemoryStore()
    ) -> PlannerDecision? {
        nextStep(
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            selectedStrategy: .testDefault
        )
    }

    func plan(failure: FailureClass, state: ReasoningPlanningState) -> [RecoveryPlan] {
        RecoveryPlanner().plan(failure: failure, state: state)
    }

    func bestRecoveryPlan(failure: FailureClass, state: ReasoningPlanningState) -> RecoveryPlan? {
        RecoveryPlanner().bestRecoveryPlan(failure: failure, state: state)
    }

    func graphRecoveryEdges(failedEdgeID: String, taskGraphStore: TaskLedgerStore) -> [TaskRecordEdge] {
        RecoveryPlanner().graphRecoveryEdges(failedEdgeID: failedEdgeID, taskGraphStore: taskGraphStore)
    }
}

extension CodePlanner {
    func nextStep(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore
    ) -> PlannerDecision? {
        nextStep(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore,
            selectedStrategy: .testDefault
        )
    }
}

extension UnifiedMemoryStore {
    func recordFixPattern(_ pattern: FixPattern, success: Bool) {
        appMemory.recordFixPattern(pattern, success: success)
    }
}

extension BuildTool {
    static var spm: Self { .swiftPackage }
}

extension RepositorySnapshot {
    init(
        id: String,
        workspaceRoot: String,
        files: [RepositoryFile],
        symbols _: [String] = [],
        buildTool: BuildTool,
        activeBranch: String?,
        isGitDirty: Bool
    ) {
        self.init(
            id: id,
            workspaceRoot: workspaceRoot,
            buildTool: buildTool,
            files: files,
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: activeBranch,
            isGitDirty: isGitDirty
        )
    }

    init(
        id: String,
        workspaceRoot: String,
        branch: String,
        dirty: Bool,
        trackedFileCount _: Int,
        fileIndex: [RepositoryFile]
    ) {
        self.init(
            id: id,
            workspaceRoot: workspaceRoot,
            buildTool: .swiftPackage,
            files: fileIndex,
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: branch,
            isGitDirty: dirty
        )
    }
}

extension Observation {
    init(
        app: String?,
        windowTitle: String?,
        url: String?,
        elements: [UnifiedElement],
        focusedElement: String?
    ) {
        self.init(
            app: app,
            windowTitle: windowTitle,
            url: url,
            focusedElementID: focusedElement,
            elements: elements
        )
    }
}

extension PlanningState {
    init(
        id: PlanningStateID,
        app: String,
        windowTitle _: String? = nil,
        url: String? = nil,
        focusedRole: String? = nil,
        focusedLabel _: String? = nil,
        keyboardFocused _: Bool = false,
        modalClass: String? = nil,
        scrollable _: Bool = false,
        elementDensity _: PlanningStateDensity = .empty,
        domain: String? = nil,
        agentKind _: AgentKind = .os
    ) {
        self.init(
            id: id,
            clusterKey: StateClusterKey(rawValue: id.rawValue),
            appID: app,
            domain: domain ?? url,
            windowClass: nil,
            taskPhase: nil,
            focusedRole: focusedRole,
            modalClass: modalClass,
            navigationClass: nil,
            controlContext: nil
        )
    }
}

enum PlanningStateDensity {
    case empty
}

extension ReasoningPlanningState {
    init(
        agentKind: AgentKind,
        repoOpen: Bool,
        modalPresent: Bool,
        patchApplied: Bool,
        testsObserved: Bool
    ) {
        self.init(
            agentKind: agentKind,
            goalDescription: "test goal",
            activeApplication: nil,
            targetApplication: nil,
            currentDomain: nil,
            targetDomain: nil,
            visibleTargets: [],
            repoOpen: repoOpen,
            repoDirty: false,
            buildSucceeded: nil,
            failingTests: nil,
            testsObserved: testsObserved,
            patchApplied: patchApplied,
            modalPresent: modalPresent,
            preferredWorkspacePath: nil,
            candidateWorkspacePaths: [],
            workspaceRoot: repoOpen ? "/tmp/workspace" : nil,
            riskPenalty: 0
        )
    }

    init(
        agentKind: AgentKind,
        goalDescription: String = "test goal",
        activeApplication: String? = nil,
        targetApplication: String? = nil,
        currentDomain: String? = nil,
        targetDomain: String? = nil,
        visibleTargets: [String] = [],
        repoOpen: Bool,
        repoDirty: Bool = false,
        buildSucceeded: Bool? = nil,
        failingTests: Int? = nil,
        testsObserved: Bool,
        patchApplied: Bool,
        modalPresent: Bool,
        preferredWorkspacePath: String? = nil,
        candidateWorkspacePaths: [String] = [],
        workspaceRoot: String? = nil,
        riskPenalty: Double = 0
    ) {
        let taskContext = TaskContext(
            goal: Goal(
                description: goalDescription,
                targetApp: targetApplication,
                targetDomain: targetDomain,
                workspaceRoot: workspaceRoot,
                preferredAgentKind: agentKind
            ),
            agentKind: agentKind,
            workspaceRoot: workspaceRoot,
            phases: agentKind == .code ? [.engineering] : [.operatingSystem]
        )
        let observation = Observation(
            app: activeApplication,
            windowTitle: activeApplication,
            url: currentDomain,
            focusedElementID: nil,
            elements: visibleTargets.map {
                UnifiedElement(id: $0, source: .ax, role: "AXButton", label: $0, confidence: 1.0)
            }
        )
        let repositorySnapshot = repoOpen
            ? RepositorySnapshot(
                id: "compat-repo",
                workspaceRoot: workspaceRoot ?? "/tmp/workspace",
                buildTool: .swiftPackage,
                files: candidateWorkspacePaths.map { RepositoryFile(path: $0, isDirectory: false) },
                symbolGraph: SymbolGraph(),
                dependencyGraph: DependencyGraph(),
                testGraph: TestGraph(),
                activeBranch: "main",
                isGitDirty: repoDirty
            )
            : nil
        let worldState = WorldState(
            observationHash: "compat-state",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "compat|\(goalDescription.replacingOccurrences(of: " ", with: "-"))"),
                clusterKey: StateClusterKey(rawValue: "compat|\(goalDescription.replacingOccurrences(of: " ", with: "-"))"),
                appID: activeApplication ?? targetApplication ?? "Compat",
                domain: currentDomain,
                windowClass: nil,
                taskPhase: repoOpen ? "engineering" : "browse",
                focusedRole: nil,
                modalClass: modalPresent ? "dialog" : nil,
                navigationClass: nil,
                controlContext: nil
            ),
            observation: observation,
            repositorySnapshot: repositorySnapshot,
            lastAction: patchApplied ? ActionIntent(app: activeApplication ?? "Compat", action: "edit_file") : nil
        )
        self.init(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(
                preferredFixPath: preferredWorkspacePath,
                riskPenalty: riskPenalty
            )
        )
    }
}

extension PlanEvaluator {
    convenience init() {
        self.init(workflowRetriever: WorkflowRetriever())
    }
}

extension MemoryDecisionBias {
    var total: Double { totalBias }
}

extension MemoryDecisionBiasCalculator {
    convenience init() {
        self.init(memoryStore: UnifiedMemoryStore())
    }

    func bias(
        plan: PlanCandidate,
        memoryInfluence _: MemoryInfluence,
        goal: Goal,
        worldState: WorldState,
        taskContext: TaskContext,
        selectedStrategy: SelectedStrategy
    ) -> MemoryDecisionBias {
        bias(
            plan: plan,
            goal: goal,
            worldState: worldState,
            taskContext: taskContext,
            selectedStrategy: selectedStrategy
        )
    }

    func biasScore(
        plan: PlanCandidate,
        memoryInfluence _: MemoryInfluence,
        goal: Goal,
        worldState: WorldState,
        taskContext: TaskContext,
        selectedStrategy: SelectedStrategy
    ) -> Double {
        biasScore(
            plan: plan,
            goal: goal,
            worldState: worldState,
            taskContext: taskContext,
            selectedStrategy: selectedStrategy
        )
    }
}

extension StrategySelector {
    convenience init(workflowRetriever _: WorkflowRetriever) {
        self.init()
    }
}

extension TraceEvent {
    init(
        sessionID: String,
        taskID: String?,
        stepID: Int,
        toolName: String,
        actionName: String,
        agentKind: String,
        planningStateID: String,
        selectedElementLabel: String?,
        selectedElementID: String?,
        success: Bool,
        verified: Bool,
        workspaceRelativePath: String? = nil
    ) {
        self.init(
            sessionID: sessionID,
            taskID: taskID,
            stepID: stepID,
            toolName: toolName,
            actionName: actionName,
            selectedElementID: selectedElementID,
            selectedElementLabel: selectedElementLabel,
            planningStateID: planningStateID,
            verified: verified,
            success: success,
            agentKind: agentKind,
            workspaceRelativePath: workspaceRelativePath,
            elapsedMs: 0
        )
    }
}

extension VerifiedTransition {
    init(
        fromPlanningStateID: PlanningStateID,
        toPlanningStateID: PlanningStateID,
        actionContractID: String,
        postconditionClass: PostconditionClass,
        verified: Bool,
        latencyMs: Int
    ) {
        self.init(
            fromPlanningStateID: fromPlanningStateID,
            toPlanningStateID: toPlanningStateID,
            actionContractID: actionContractID,
            postconditionClass: postconditionClass,
            verified: verified,
            failureClass: nil,
            latencyMs: latencyMs
        )
    }
}

extension TraceClusterer {
    func cluster(segments: [TraceSegment]) -> [TraceCluster] {
        cluster(traces: segments.map(\.events))
    }
}

extension TraceCluster {
    var segments: [TraceSegment] {
        traces.enumerated().map { index, trace in
            TraceSegment(
                id: "cluster|\(fingerprint)|\(index)",
                taskID: trace.first?.taskID,
                sessionID: trace.first?.sessionID ?? "cluster",
                agentKind: AgentKind(rawValue: trace.first?.agentKind ?? AgentKind.os.rawValue) ?? .os,
                events: trace
            )
        }
    }
}

extension WorkflowMatcher {
    func match(currentState: AbstractTaskState, workflowIndex: WorkflowIndex) -> [Match] {
        match(currentState: currentState, workflowIndex: workflowIndex, selectedStrategy: .testDefault)
    }
}

extension WorkflowParameterizer {
    func parameterize(
        goalPattern: String,
        segments: [TraceSegment]
    ) -> ParameterizedWorkflow? {
        parameterize(goalPattern: goalPattern, traces: segments.map(\.events))
    }
}

extension DiagnosticsWriter {
    func writeTaskGraph(_ store: TaskLedgerStore) {
        writeTaskLedger(store)
    }
}

extension EnvironmentMonitor {
    func reconcile(
        worldState: WorldState,
        postconditions: [Postcondition],
        observation _: Observation
    ) -> ReconciliationResult {
        reconcile(worldState: worldState, postconditions: postconditions)
    }
}

extension ActionIntent {
    init(action: String, app: String) {
        self.init(app: app, action: action)
    }
}

extension LLMRepairAdvisor {
    func advise(
        errorSignature: String,
        faultCandidates: [String],
        memoryInfluence: MemoryInfluence
    ) async -> RepairAdvice {
        await advise(
            errorSignature: errorSignature,
            faultCandidates: faultCandidates,
            memoryInfluence: memoryInfluence,
            selectedStrategy: .testDefault
        )
    }
}

extension LLMTargetResolver {
    func resolve(
        goal: String,
        domSummary: String,
        visibleElements: [String]
    ) async -> LLMTargetResolution {
        await resolve(
            goal: goal,
            domSummary: domSummary,
            visibleElements: visibleElements,
            selectedStrategy: .testDefault
        )
    }
}

extension LedgerNavigator {
    func expand(
        from nodeID: String,
        in graph: TaskLedger,
        scorer: LedgerScorer,
        goal: Goal? = nil
    ) -> [ScoredPath] {
        expand(
            from: nodeID,
            in: graph,
            scorer: scorer,
            goal: goal,
            allowedFamilies: OperatorFamily.allCases
        )
    }

    func bestNextEdge(
        from nodeID: String,
        in graph: TaskLedger,
        scorer: LedgerScorer,
        goal: Goal? = nil
    ) -> TaskRecordEdge? {
        bestNextEdge(
            from: nodeID,
            in: graph,
            scorer: scorer,
            goal: goal,
            allowedFamilies: OperatorFamily.allCases
        )
    }
}

extension CandidateGenerator {
    convenience init(
        stateMemoryIndex: StateMemoryIndex,
        planningGraphStore: GraphStore,
        maxCandidates: Int = 6
    ) {
        self.init(
            stateMemoryIndex: stateMemoryIndex,
            graphStore: planningGraphStore,
            maxCandidates: maxCandidates
        )
    }

    func generate(
        compressedState: CompressedUIState,
        abstractState: AbstractTaskState,
        llmSchemas: [ActionSchema] = []
    ) -> [Candidate] {
        generate(
            compressedState: compressedState,
            abstractState: abstractState,
            planningStateID: PlanningStateID(rawValue: abstractState.rawValue),
            llmSchemas: llmSchemas
        )
    }
}

extension SearchController {
    func search(
        compressedState: CompressedUIState,
        abstractState: AbstractTaskState,
        llmSchemas: [ActionSchema] = [],
        evaluate: (Candidate) -> CandidateResult?
    ) -> CandidateResult? {
        search(
            compressedState: compressedState,
            abstractState: abstractState,
            planningStateID: PlanningStateID(rawValue: abstractState.rawValue),
            llmSchemas: llmSchemas,
            evaluate: evaluate
        )
    }
}

struct PlanningEdge: Sendable {
    let id: String
    let fromState: AbstractTaskState
    let toState: AbstractTaskState
    let schema: ActionSchema
    private(set) var successRate: Double
    private(set) var attempts: Int
    private(set) var successes: Int
    private(set) var totalLatencyMs: Int

    init(
        id: String = UUID().uuidString,
        fromState: AbstractTaskState,
        toState: AbstractTaskState,
        schema: ActionSchema,
        successRate: Double = 0.5,
        attempts: Int = 0,
        successes: Int = 0,
        totalLatencyMs: Int = 0
    ) {
        self.id = id
        self.fromState = fromState
        self.toState = toState
        self.schema = schema
        self.successRate = successRate
        self.attempts = attempts
        self.successes = successes
        self.totalLatencyMs = totalLatencyMs
    }

    var score: Double { successRate }

    mutating func recordSuccess(latencyMs: Int = 0) {
        attempts += 1
        successes += 1
        totalLatencyMs += latencyMs
        successRate = Double(successes) / Double(attempts)
    }

    mutating func recordFailure(latencyMs: Int = 0) {
        attempts += 1
        totalLatencyMs += latencyMs
        successRate = attempts == 0 ? successRate : Double(successes) / Double(attempts)
    }
}

struct PlanningGraphEngine {
    private(set) var edges: [PlanningEdge]

    init(edges: [PlanningEdge] = []) {
        self.edges = edges
    }

    var edgeCount: Int { edges.count }

    var allStates: Set<AbstractTaskState> {
        Set(edges.flatMap { [$0.fromState, $0.toState] })
    }

    mutating func addEdge(_ edge: PlanningEdge) {
        edges.append(edge)
    }

    func candidateEdges(from state: AbstractTaskState) -> [PlanningEdge] {
        edges
            .filter { $0.fromState == state }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.schema.name < rhs.schema.name
                }
                return lhs.score > rhs.score
            }
    }

    func bestEdge(from state: AbstractTaskState) -> PlanningEdge? {
        candidateEdges(from: state).first
    }

    mutating func recordOutcome(edgeID: String, success: Bool, latencyMs: Int = 0) {
        guard let index = edges.firstIndex(where: { $0.id == edgeID }) else { return }
        if success {
            edges[index].recordSuccess(latencyMs: latencyMs)
        } else {
            edges[index].recordFailure(latencyMs: latencyMs)
        }
    }

    mutating func pruneWeakEdges(belowRate: Double, minAttempts: Int) {
        edges.removeAll { $0.attempts >= minAttempts && $0.successRate < belowRate }
    }

    mutating func recordOutcome(
        fromState: String,
        toState: String,
        schema: ActionSchema,
        success: Bool
    ) {
        guard let from = AbstractTaskState(rawValue: fromState),
              let to = AbstractTaskState(rawValue: toState)
        else {
            return
        }

        if let index = edges.firstIndex(where: {
            $0.fromState == from && $0.toState == to && $0.schema.name == schema.name
        }) {
            if success {
                edges[index].recordSuccess()
            } else {
                edges[index].recordFailure()
            }
            return
        }

        var edge = PlanningEdge(fromState: from, toState: to, schema: schema, successRate: 0, attempts: 0, successes: 0)
        if success {
            edge.recordSuccess()
        } else {
            edge.recordFailure()
        }
        edges.append(edge)
    }

    func validActions(for state: AbstractTaskState) -> [ActionSchema] {
        candidateEdges(from: state).map(\.schema)
    }
}

extension GraphStore {
    @discardableResult
    func addEdge(_ edge: PlanningEdge) -> EdgeTransition? {
        let fromStateID = PlanningStateID(rawValue: edge.fromState.rawValue)
        let toStateID = PlanningStateID(rawValue: edge.toState.rawValue)
        let contract = ActionContract(
            id: edge.id,
            skillName: edge.schema.name,
            targetRole: nil,
            targetLabel: nil,
            locatorStrategy: "compat"
        )
        let fromState = PlanningState(
            id: fromStateID,
            clusterKey: StateClusterKey(rawValue: fromStateID.rawValue),
            appID: "Compat",
            domain: nil,
            windowClass: nil,
            taskPhase: edge.fromState.rawValue,
            focusedRole: nil,
            modalClass: nil,
            navigationClass: nil,
            controlContext: nil
        )
        let toState = PlanningState(
            id: toStateID,
            clusterKey: StateClusterKey(rawValue: toStateID.rawValue),
            appID: "Compat",
            domain: nil,
            windowClass: nil,
            taskPhase: edge.toState.rawValue,
            focusedRole: nil,
            modalClass: nil,
            navigationClass: nil,
            controlContext: nil
        )

        let successes = max(edge.successes, 1)
        for _ in 0..<successes {
            recordTransition(
                VerifiedTransition(
                    fromPlanningStateID: fromStateID,
                    toPlanningStateID: toStateID,
                    actionContractID: contract.id,
                    postconditionClass: .navigationOccurred,
                    verified: true,
                    failureClass: nil,
                    latencyMs: 0
                ),
                actionContract: contract,
                fromState: fromState,
                toState: toState
            )
        }
        let failures = max(edge.attempts - edge.successes, 0)
        for _ in 0..<failures {
            recordTransition(
                VerifiedTransition(
                    fromPlanningStateID: fromStateID,
                    toPlanningStateID: toStateID,
                    actionContractID: contract.id,
                    postconditionClass: .actionFailed,
                    verified: false,
                    failureClass: FailureClass.actionFailed.rawValue,
                    latencyMs: 0
                ),
                actionContract: contract,
                fromState: fromState,
                toState: toState
            )
        }
        _ = promoteEligibleEdges()
        return (outgoingStableEdges(from: fromStateID) + outgoingCandidateEdges(from: fromStateID))
            .first { $0.actionContractID == contract.id }
    }
}
