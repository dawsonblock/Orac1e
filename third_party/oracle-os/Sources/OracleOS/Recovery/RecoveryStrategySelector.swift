import Foundation

public struct RecoverySelection: @unchecked Sendable {
    public let orderedStrategies: [any RecoveryStrategy]
    public let promptDiagnostics: PromptDiagnostics?

    public init(
        orderedStrategies: [any RecoveryStrategy],
        promptDiagnostics: PromptDiagnostics? = nil
    ) {
        self.orderedStrategies = orderedStrategies
        self.promptDiagnostics = promptDiagnostics
    }
}

@MainActor
public struct RecoveryStrategySelector {
    private let registry: RecoveryRegistry
    private let promptEngine: PromptEngine

    public init(
        registry: RecoveryRegistry,
        promptEngine: PromptEngine = PromptEngine()
    ) {
        self.registry = registry
        self.promptEngine = promptEngine
    }

    public func orderedStrategies(
        for failure: FailureClass,
        state: WorldState,
memoryStore: UnifiedMemoryStore?
    ) -> [any RecoveryStrategy] {
        select(
            for: failure,
            state: state,
            memoryStore: memoryStore
        ).orderedStrategies
    }

    public func select(
        for failure: FailureClass,
        state: WorldState,
memoryStore: UnifiedMemoryStore?
    ) -> RecoverySelection {
        let memoryRouter = memoryStore.map { MemoryRouter(memoryStore: $0) }
        let preferredStrategy = memoryRouter?.preferredRecoveryStrategy(
            app: state.observation.app ?? "unknown"
        )
        let memoryInfluence = memoryRouter?.influence(
            for: MemoryQueryContext(
                app: state.observation.app,
                failureClass: failure,
                planningState: state.planningState
            )
        )
        let strategies = registry.strategies(for: failure)
        let orderedStrategies = strategies.sorted { lhs, rhs in
            let lhsBias = memoryStrategyBias(
                lhs.name, preferred: preferredStrategy, influence: memoryInfluence
            )
            let rhsBias = memoryStrategyBias(
                rhs.name, preferred: preferredStrategy, influence: memoryInfluence
            )
            if lhsBias != rhsBias { return lhsBias > rhsBias }
            if lhs.layer != rhs.layer { return lhs.layer < rhs.layer }
            return lhs.name < rhs.name
        }

        let promptDiagnostics = promptEngine.recoverySelection(
            failure: failure,
            state: state,
            orderedStrategies: orderedStrategies.map(\.name),
            preferredStrategy: preferredStrategy
        ).diagnostics

        return RecoverySelection(
            orderedStrategies: orderedStrategies,
            promptDiagnostics: promptDiagnostics
        )
    }

    private func memoryStrategyBias(
        _ strategyName: String,
        preferred: String?,
        influence: MemoryInfluence?
    ) -> Double {
        var bias = 0.0
        if strategyName == preferred {
            bias += 1.0
        }
        if let influence, strategyName == influence.preferredRecoveryStrategy {
            bias += 0.5
        }
        return bias
    }
}
