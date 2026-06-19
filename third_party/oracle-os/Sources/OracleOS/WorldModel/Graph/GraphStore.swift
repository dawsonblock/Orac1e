import Foundation

public final class GraphStore {
    private let candidateGraph: CandidateGraph
    private let stableGraph: StableGraph
    private let persistence: GraphPersistence?
    private let maintenance: GraphMaintenance
    private var planningStates: [PlanningStateID: PlanningState]
    private var actionContracts: [String: ActionContract]
    private let storeLock = NSRecursiveLock()

    public init(databaseURL: URL) {
        let persistence = try? GraphPersistence(databaseURL: databaseURL)
        let snapshot = persistence?.loadSnapshot() ?? GraphSnapshot()
        self.persistence = persistence
        self.candidateGraph = snapshot.candidateGraph
        self.stableGraph = snapshot.stableGraph
        self.actionContracts = snapshot.actionContracts
        self.planningStates = snapshot.planningStates
        self.maintenance = GraphMaintenance()
    }

    public convenience init() {
        self.init(databaseURL: GraphStore.defaultDatabaseURL())
    }

    public func recordTransition(
        _ transition: VerifiedTransition,
        actionContract: ActionContract? = nil,
        fromState: PlanningState? = nil,
        toState: PlanningState? = nil
    ) {
        storeLock.lock()
        defer { storeLock.unlock() }

        let governedTransition = sanitize(transition)
        if let fromState {
            planningStates[fromState.id] = fromState
            persistence?.upsertPlanningState(fromState)
        }
        if let toState {
            planningStates[toState.id] = toState
            persistence?.upsertPlanningState(toState)
        }
        candidateGraph.record(governedTransition)
        persistence?.upsertCandidateEdge(candidateGraph.edges[edgeKey(for: governedTransition)])
        if let actionContract {
            actionContracts[actionContract.id] = actionContract
            persistence?.upsertActionContract(actionContract)
        }
        persistence?.persistGraphStats(globalStats())
    }

    public func recordFailure(
        state: PlanningState,
        actionContract: ActionContract,
        failure: FailureClass,
        ambiguityScore: Double? = nil,
        recoveryTagged: Bool = false
    ) {
        storeLock.lock()
        defer { storeLock.unlock() }

        planningStates[state.id] = state
        actionContracts[actionContract.id] = actionContract
        persistence?.upsertPlanningState(state)
        persistence?.upsertActionContract(actionContract)

        let transition = VerifiedTransition(
            fromPlanningStateID: state.id,
            toPlanningStateID: state.id,
            actionContractID: actionContract.id,
            agentKind: actionContract.agentKind,
            domain: actionContract.domain,
            workspaceRelativePath: actionContract.workspaceRelativePath,
            commandCategory: actionContract.commandCategory,
            plannerFamily: actionContract.plannerFamily,
            postconditionClass: .actionFailed,
            verified: false,
            failureClass: failure.rawValue,
            latencyMs: 0,
            targetAmbiguityScore: ambiguityScore,
            recoveryTagged: recoveryTagged,
            approvalRequired: false,
            approvalOutcome: nil,
            knowledgeTier: recoveryTagged ? .recovery : .candidate
        )

        candidateGraph.record(transition)
        let edgeID = edgeKey(for: transition)
        if let edge = candidateGraph.edges[edgeID] {
            persistence?.upsertCandidateEdge(edge)
            persistence?.recordFailure(
                edgeID: edge.edgeID,
                stateID: state.id.rawValue,
                actionContractID: actionContract.id,
                failureClass: failure.rawValue,
                timestamp: transition.timestamp,
                ambiguityScore: ambiguityScore,
                recoveryTagged: recoveryTagged
            )
        }
        persistence?.persistGraphStats(globalStats())
    }

    @discardableResult
    public func promoteEligibleEdges(now: Date = Date()) -> [EdgeTransition] {
        storeLock.lock()
        defer { storeLock.unlock() }

        let promoted = maintenance.promoteEligibleEdges(
            candidateGraph: candidateGraph,
            stableGraph: stableGraph,
            globalVerifiedSuccessRate: globalSuccessRate(),
            now: now
        )
        for edge in promoted {
            persistence?.upsertStableEdge(edge)
        }
        persistence?.persistGraphStats(globalStats())
        return promoted
    }

    @discardableResult
    public func pruneOrDemoteEdges(now: Date = Date()) -> [String] {
        storeLock.lock()
        defer { storeLock.unlock() }

        let removed = maintenance.pruneOrDemoteEdges(
            candidateGraph: candidateGraph,
            stableGraph: stableGraph,
            now: now
        )
        for edgeID in removed {
            persistence?.deleteStableEdge(edgeID: edgeID)
        }
        persistence?.persistGraphStats(globalStats())
        return removed
    }

    public func promoteStableGraph() {
        _ = promoteEligibleEdges()
    }

    public func outgoingEdges(from planningStateID: PlanningStateID) -> [EdgeTransition] {
        outgoingStableEdges(from: planningStateID)
    }

    public func outgoingCandidateEdges(from planningStateID: PlanningStateID) -> [EdgeTransition] {
        storeLock.lock()
        defer { storeLock.unlock() }

        return candidateGraph.edges.values
            .filter {
                $0.fromPlanningStateID == planningStateID
                    && $0.knowledgeTier == .candidate
                    && $0.successes > 0
            }
            .sorted { $0.cost < $1.cost }
    }

    public func outgoingStableEdges(from planningStateID: PlanningStateID) -> [EdgeTransition] {
        storeLock.lock()
        defer { storeLock.unlock() }
        return stableGraph.outgoing(from: planningStateID)
    }

    public func actionContract(for id: String) -> ActionContract? {
        storeLock.lock()
        defer { storeLock.unlock() }
        return actionContracts[id]
    }

    public func planningState(for id: PlanningStateID) -> PlanningState? {
        storeLock.lock()
        defer { storeLock.unlock() }
        return planningStates[id]
    }

    public func stableEdge(for id: String) -> EdgeTransition? {
        storeLock.lock()
        defer { storeLock.unlock() }
        return stableGraph.edges[id]
    }

    public func globalSuccessRate() -> Double {
        storeLock.lock()
        defer { storeLock.unlock() }
        let stats = globalStats()
        guard stats.attempts > 0 else { return 0 }
        return Double(stats.successes) / Double(stats.attempts)
    }

    public func allStableEdges() -> [EdgeTransition] {
        storeLock.lock()
        defer { storeLock.unlock() }
        return stableGraph.edges.values.sorted { $0.edgeID < $1.edgeID }
    }

    public func allCandidateEdges() -> [EdgeTransition] {
        storeLock.lock()
        defer { storeLock.unlock() }
        return candidateGraph.edges.values.sorted { $0.edgeID < $1.edgeID }
    }

    public static func defaultDatabaseURL() -> URL {
        OracleProductPaths.graphDatabaseURL
    }

    private func edgeKey(for transition: VerifiedTransition) -> String {
        [
            transition.fromPlanningStateID.rawValue,
            transition.actionContractID,
            transition.postconditionClass.rawValue,
        ].joined(separator: "|")
    }

    private func sanitize(_ transition: VerifiedTransition) -> VerifiedTransition {
        var governedTier = transition.knowledgeTier

        if transition.recoveryTagged {
            governedTier = .recovery
        } else if transition.knowledgeTier == .stable {
            governedTier = .candidate
        }

        guard governedTier != transition.knowledgeTier else {
            return transition
        }

        return VerifiedTransition(
            fromPlanningStateID: transition.fromPlanningStateID,
            toPlanningStateID: transition.toPlanningStateID,
            actionContractID: transition.actionContractID,
            agentKind: transition.agentKind,
            domain: transition.domain,
            workspaceRelativePath: transition.workspaceRelativePath,
            commandCategory: transition.commandCategory,
            plannerFamily: transition.plannerFamily,
            postconditionClass: transition.postconditionClass,
            verified: transition.verified,
            failureClass: transition.failureClass,
            latencyMs: transition.latencyMs,
            targetAmbiguityScore: transition.targetAmbiguityScore,
            recoveryTagged: transition.recoveryTagged,
            approvalRequired: transition.approvalRequired,
            approvalOutcome: transition.approvalOutcome,
            knowledgeTier: governedTier,
            timestamp: transition.timestamp
        )
    }

    private func globalStats() -> GraphStats {
        let attempts = candidateGraph.edges.values.reduce(0) { $0 + $1.attempts }
        let successes = candidateGraph.edges.values.reduce(0) { $0 + $1.successes }
        return GraphStats(attempts: attempts, successes: successes, updatedAt: Date().timeIntervalSince1970)
    }
}
