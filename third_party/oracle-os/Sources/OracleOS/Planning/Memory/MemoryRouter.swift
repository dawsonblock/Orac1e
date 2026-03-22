import Foundation

public struct MemoryRouter {
    private let unifiedStore: UnifiedMemoryStore

    public init(memoryStore: UnifiedMemoryStore? = nil) {
        self.unifiedStore = memoryStore ?? UnifiedMemoryStore()
    }

    public func influence(for context: MemoryQueryContext) -> MemoryInfluence {
        unifiedStore.influence(for: context)
    }

    public func rankingBias(
        label: String?,
        app: String?,
        goalDescription: String = "",
        repositorySnapshot: RepositorySnapshot? = nil,
        planningState: PlanningState? = nil
    ) -> Double {
        influence(
            for: MemoryQueryContext(
                goalDescription: goalDescription,
                app: app,
                label: label,
                repositorySnapshot: repositorySnapshot,
                planningState: planningState
            )
        ).executionRankingBias
    }

    public func preferredRecoveryStrategy(
        app: String
    ) -> String? {
        influence(
            for: MemoryQueryContext(app: app)
        ).preferredRecoveryStrategy
    }

    public func preferredFixPath(
        errorSignature: String?,
        workspaceRoot: String? = nil,
        repositorySnapshot: RepositorySnapshot? = nil
    ) -> String? {
        influence(
            for: MemoryQueryContext(
                goalDescription: errorSignature ?? "",
                workspaceRoot: workspaceRoot,
                errorSignature: errorSignature,
                repositorySnapshot: repositorySnapshot
            )
        ).preferredFixPath
    }

    public func commandBias(
        category: String?,
        workspaceRoot: String?,
        repositorySnapshot: RepositorySnapshot? = nil
    ) -> Double {
        let influence = influence(
            for: MemoryQueryContext(
                workspaceRoot: workspaceRoot,
                commandCategory: category,
                repositorySnapshot: repositorySnapshot
            )
        )
        return influence.commandBias
    }

    public func workflowActionBias(
        contract: ActionContract,
        app: String?,
        goalDescription: String = "",
        workspaceRoot: String? = nil
    ) -> Double {
        // This remains slightly specialized for workflow bias scoring
        let ctx = MemoryQueryContext(
            goalDescription: goalDescription,
            app: app,
            label: contract.targetLabel,
            workspaceRoot: workspaceRoot,
            commandCategory: contract.commandCategory
        )
        let influence = influence(for: ctx)
        
        var bias = influence.executionRankingBias + influence.commandBias
        if let preferredFixPath = influence.preferredFixPath,
           preferredFixPath == contract.workspaceRelativePath {
            bias += 0.15
        }
        return min(bias, 0.3)
    }
}
