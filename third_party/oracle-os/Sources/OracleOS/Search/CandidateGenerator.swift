// CandidateGenerator.swift — Memory-first candidate generation.
//
// Generates action candidates for a given abstract state. The priority
// order enforces memory-driven behaviour:
//
//   1. StateMemory suggestions (historically successful actions)
//   2. GraphStore valid actions (graph-constrained edges)
//   3. LLM fallback candidates (only when memory and graph are empty)
//
// The LLM should fill gaps, not lead action selection by default.

import Foundation

/// Generates ``Candidate`` actions for a given state using a
/// memory-first, graph-second, LLM-last priority order.
@MainActor
public final class CandidateGenerator {
    private let stateMemoryIndex: StateMemoryIndex
    private let graphStore: GraphStore
    /// Maximum candidates returned per generation cycle.
    public let maxCandidates: Int

    public init(
        stateMemoryIndex: StateMemoryIndex,
        graphStore: GraphStore,
        maxCandidates: Int = 6
    ) {
        self.stateMemoryIndex = stateMemoryIndex
        self.graphStore = graphStore
        self.maxCandidates = maxCandidates
    }

    /// Generate candidates for the given compressed UI state and abstract
    /// task state. LLM-provided schemas are used only as a fallback.
    ///
    /// - Parameters:
    ///   - compressedState: The current compressed UI state from perception.
    ///   - abstractState: The current abstract task state for graph lookup.
    ///   - llmSchemas: Optional schemas provided by the LLM when memory
    ///     and graph cannot fully populate the candidate list.
    /// - Returns: Up to ``maxCandidates`` candidates in priority order.
    public func generate(
        compressedState: CompressedUIState,
        abstractState: AbstractTaskState,
        planningStateID: PlanningStateID,
        llmSchemas: [ActionSchema] = []
    ) -> [Candidate] {
        var candidates: [Candidate] = []

        // 1. Memory suggestions — historically successful actions.
        candidates += memoryCandidates(for: compressedState)

        // 2. Graph suggestions — valid edges from the current state.
        candidates += graphCandidates(for: planningStateID, excluding: candidates)

        // 3. LLM fallback — only when gaps remain.
        candidates += llmCandidates(from: llmSchemas, excluding: candidates)

        return Array(candidates.prefix(maxCandidates))
    }

    // MARK: - Private

    /// Attempt to infer the original `ActionSchemaKind` from a stored action name.
    /// This assumes that the prefix before the first underscore corresponds
    /// to the `rawValue` of `ActionSchemaKind` (e.g., "click_Save" -> "click").
    /// If inference fails, `.custom` is used as a safe fallback.
    private func inferKind(for actionName: String) -> ActionSchemaKind {
        // Extract prefix before first underscore, if any.
        let components = actionName.split(separator: "_", maxSplits: 1)
        guard let prefix = components.first else {
            return .custom
        }
        return ActionSchemaKind(rawValue: String(prefix)) ?? .custom
    }

    private func memoryCandidates(for state: CompressedUIState) -> [Candidate] {
        let stats = stateMemoryIndex.likelyActions(for: state)
        return stats.compactMap { stat in
            guard !stat.actionName.isEmpty else { return nil }
            return Candidate(
                hypothesis: "Historically successful (\(Int(stat.successRate * 100))% rate over \(stat.attempts) attempts)",
                schema: ActionSchema(name: stat.actionName, kind: inferKind(for: stat.actionName)),
                source: .memory
            )
        }
    }

    private func graphCandidates(
        for planningStateID: PlanningStateID,
        excluding existing: [Candidate]
    ) -> [Candidate] {
        let existingNames = Set(existing.map(\.schema.name))
        
        let edges = graphStore.outgoingStableEdges(from: planningStateID) +
                    graphStore.outgoingCandidateEdges(from: planningStateID)
        let contracts = edges.compactMap { graphStore.actionContract(for: $0.actionContractID) }

        return contracts
            .filter { !existingNames.contains($0.skillName) }
            .map { contract in
                let schema = ActionSchema(
                    name: contract.skillName,
                    kind: inferKind(for: contract.skillName)
                )
                return Candidate(
                    hypothesis: "Graph-valid action from planning state \(planningStateID.rawValue)",
                    schema: schema,
                    source: .graph
                )
            }
    }

    private func llmCandidates(
        from schemas: [ActionSchema],
        excluding existing: [Candidate]
    ) -> [Candidate] {
        let existingNames = Set(existing.map(\.schema.name))
        return schemas
            .filter { !existingNames.contains($0.name) }
            .map { schema in
                Candidate(
                    hypothesis: "LLM-generated fallback action",
                    schema: schema,
                    source: .llmFallback
                )
            }
    }
}
