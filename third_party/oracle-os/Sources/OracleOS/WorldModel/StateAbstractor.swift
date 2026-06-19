import Foundation

/// Derives an ``AbstractTaskState`` from the world model and planning context.
///
/// This is the critical abstraction layer that prevents graph explosion.
/// Raw UI noise (scroll positions, focus rings, minor DOM mutations) must
/// **not** produce distinct abstract states. Only task-meaningful transitions
/// create new nodes.
public struct StateAbstractor: Sendable {
    public init() {}

    /// Derive an ``AbstractTaskState`` from a ``WorldState``.
    public func abstractState(from worldState: WorldState) -> AbstractTaskState {
        let planning = worldState.planningState

        // Modal / permission dialogs take priority
        if let modalClass = planning.modalClass {
            if modalClass.lowercased().contains("permission") || modalClass.lowercased().contains("auth") {
                return .permissionDialogActive
            }
            return .modalDialogActive
        }

        // Repository / code states
        if let repo = worldState.repositorySnapshot {
            return codeAbstractState(planning: planning, repo: repo)
        }

        // Browser / OS states
        return uiAbstractState(planning: planning, observation: worldState.observation)
    }

    /// Locate or create a ``TaskRecord`` for the given world state inside the
    /// supplied ``TaskLedger``.
    public func resolveNode(
        worldState: WorldState,
        taskGraph: TaskLedger,
        createdByAction: String? = nil
    ) -> TaskRecord {
        let abstract = abstractState(from: worldState)
        let node = TaskRecord(
            abstractState: abstract,
            planningStateID: worldState.planningState.id,
            worldSnapshotRef: worldState.observationHash,
            createdByAction: createdByAction
        )
        return taskGraph.addOrMergeNode(node)
    }

    // MARK: - Private Helpers

    private func codeAbstractState(
        planning: PlanningState,
        repo: RepositorySnapshot
    ) -> AbstractTaskState {
        let phase = planning.taskPhase?.lowercased() ?? ""

        if phase.contains("test") && phase.contains("run") {
            return .testsRunning
        }
        if phase.contains("test") && phase.contains("pass") {
            return .testsPassed
        }
        if phase.contains("fail") && phase.contains("test") {
            return .failingTestIdentified
        }
        if phase.contains("build") && phase.contains("run") {
            return .buildRunning
        }
        if phase.contains("build") && phase.contains("success") {
            return .buildSucceeded
        }
        if phase.contains("build") && phase.contains("fail") {
            return .buildFailed
        }
        if phase.contains("patch") && phase.contains("apply") {
            return .candidatePatchApplied
        }
        if phase.contains("patch") && phase.contains("verif") {
            return .patchVerified
        }
        if phase.contains("patch") && phase.contains("reject") {
            return .patchRejected
        }
        if phase.contains("patch") {
            return .candidatePatchGenerated
        }
        if phase.contains("index") {
            return .repoIndexed
        }

        return .repoLoaded
    }

    private func uiAbstractState(
        planning: PlanningState,
        observation: Observation
    ) -> AbstractTaskState {
        let domain = planning.domain?.lowercased() ?? ""
        let phase = planning.taskPhase?.lowercased() ?? ""
        let app = planning.appID.lowercased()

        if domain.contains("login") || phase.contains("login") {
            return .loginPageDetected
        }
        if phase.contains("navigation") || phase.contains("navigate") {
            return .navigationCompleted
        }
        if phase.contains("form") {
            return .formVisible
        }
        if phase.contains("explore") || phase.contains("discovery") {
            return .explorationActive
        }
        if phase.contains("complete") || phase.contains("done") {
            return .goalReached
        }
        if phase.contains("recover") {
            return .recoveryNeeded
        }

        if !app.isEmpty {
            return .pageLoaded
        }

        return .idle
    }
}
