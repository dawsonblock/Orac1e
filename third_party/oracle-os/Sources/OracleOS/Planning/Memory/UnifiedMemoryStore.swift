import Foundation

/// Unified entry point for all memory stores (App, Project, Execution, Pattern).
/// Consolidates live runtime memory and static project knowledge.
public final class UnifiedMemoryStore: @unchecked Sendable {
    public let appMemory: StrategyMemory
    private var projectMemory: ProjectMemoryStore?
    private let executionStore: ExecutionMemoryStore
    private let patternStore: PatternMemoryStore
    
    public init(appMemory: StrategyMemory = StrategyMemory()) {
        self.appMemory = appMemory
        self.executionStore = ExecutionMemoryStore(store: appMemory)
        self.patternStore = PatternMemoryStore(store: appMemory)
    }
    
    /// Binds the store to a specific project root, enabling ProjectMemory access.
    public func setWorkspaceRoot(_ root: String) {
        do {
            self.projectMemory = try ProjectMemoryStore(
                projectRootURL: URL(fileURLWithPath: root, isDirectory: true)
            )
        } catch {
            // Log error
            print("Failed to initialize ProjectMemoryStore at \(root): \(error)")
        }
    }
    
    /// Core query API that computes memory influence based on current context.
    public func influence(for context: MemoryQueryContext) -> MemoryInfluence {
        let executionBias = executionStore.rankingBias(
            label: context.label,
            app: context.app
        )
        let commandBias = patternStore.commandBias(
            category: context.commandCategory,
            workspaceRoot: context.workspaceRoot
        )
        let preferredFixPath = patternStore.preferredFixPath(
            errorSignature: context.errorSignature ?? context.goalDescription
        )
        let preferredRecoveryStrategy = context.app.flatMap {
            executionStore.preferredRecoveryStrategy(app: $0)
        }

        let projectSignals = projectMemorySignals(for: context)
        let preferredPaths = context.repositorySnapshot.map {
            projectSignals.preferredPaths(in: $0)
        } ?? []
        let avoidedPaths = context.repositorySnapshot.map {
            projectSignals.avoidedPaths(in: $0)
        } ?? []

        var notes: [String] = []
        var evidence: [MemoryEvidence] = []

        if executionBias > 0 {
            notes.append("execution memory biased ranked selection")
            evidence.append(
                MemoryEvidence(
                    tier: .execution,
                    summary: "repeated successful control use",
                    confidence: executionBias
                )
            )
        }

        if commandBias > 0 {
            notes.append("pattern memory biased command reuse")
            evidence.append(
                MemoryEvidence(
                    tier: .pattern,
                    summary: "repeated successful command use",
                    confidence: commandBias
                )
            )
        }

        if let preferredFixPath {
            notes.append("pattern memory preferred \(preferredFixPath)")
            evidence.append(
                MemoryEvidence(
                    tier: .pattern,
                    summary: "preferred fix path \(preferredFixPath)",
                    confidence: 0.5
                )
            )
        }

        if !projectSignals.refs.isEmpty {
            notes.append("project memory returned \(projectSignals.refs.count) relevant records")
            evidence.append(
                MemoryEvidence(
                    tier: .project,
                    summary: "project memory planning signals",
                    sourceRefs: projectSignals.refs.map(\.path),
                    confidence: min(1, Double(projectSignals.refs.count) * 0.1)
                )
            )
        }

        let shouldPreferExperiments = projectSignals.hasRejectedApproaches || projectSignals.hasOpenProblems
        let riskPenalty = projectSignals.hasRisks ? 0.1 : 0

        return MemoryInfluence(
            executionRankingBias: executionBias,
            commandBias: commandBias,
            preferredFixPath: preferredFixPath,
            preferredRecoveryStrategy: preferredRecoveryStrategy,
            projectMemorySignals: projectSignals,
            preferredPaths: preferredPaths,
            avoidedPaths: avoidedPaths,
            shouldPreferExperiments: shouldPreferExperiments,
            riskPenalty: riskPenalty,
            notes: notes,
            evidence: evidence
        )
    }
    
    private func projectMemorySignals(
        for context: MemoryQueryContext
    ) -> ProjectMemoryPlanningSignals {
        guard let snapshot = context.repositorySnapshot,
              (context.agentKind == .code || context.agentKind == .mixed || context.agentKind == nil)
        else {
            return ProjectMemoryPlanningSignals()
        }

        if let store = projectMemory {
            return ProjectMemoryQuery.planningSignals(
                goalDescription: context.goalDescription,
                snapshot: snapshot,
                store: store
            )
        }
        return ProjectMemoryPlanningSignals()
    }

    // MARK: - AppMemory Recording Delegates

    public func recordControl(_ control: KnownControl) {
        appMemory.recordControl(control)
    }

    public func recordFailure(_ failure: FailurePattern) {
        appMemory.recordFailure(failure)
    }

    public func recordStrategy(_ record: StrategyRecord) {
        appMemory.recordStrategy(record)
    }

    public func recordProtectedOperation(app: String, operation: String) {
        appMemory.recordProtectedOperation(app: app, operation: operation)
    }

    public func recordApproval(app: String, operation: String) {
        appMemory.recordApproval(app: app, operation: operation)
    }

    public func recordCommandResult(category: String, workspaceRoot: String, success: Bool) {
        appMemory.recordCommandResult(category: category, workspaceRoot: workspaceRoot, success: success)
    }

    // MARK: - ProjectMemory Recording Delegates

    public func recordOpenProblem(
        title: String,
        summary: String,
        knowledgeClass: KnowledgeClass,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = [],
        body: String
    ) throws {
        _ = try projectMemory?.writeOpenProblemDraft(
            title: title,
            summary: summary,
            knowledgeClass: knowledgeClass,
            affectedModules: affectedModules,
            evidenceRefs: evidenceRefs,
            sourceTraceIDs: sourceTraceIDs,
            body: body
        )
    }

    public func recordArchitectureDecision(
        title: String,
        summary: String,
        knowledgeClass: KnowledgeClass,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = [],
        body: String
    ) throws {
        _ = try projectMemory?.writeArchitectureDecisionDraft(
            title: title,
            summary: summary,
            knowledgeClass: knowledgeClass,
            affectedModules: affectedModules,
            evidenceRefs: evidenceRefs,
            sourceTraceIDs: sourceTraceIDs,
            body: body
        )
    }

    public func recordKnownGoodPattern(
        title: String,
        summary: String,
        knowledgeClass: KnowledgeClass,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = [],
        body: String
    ) throws {
        _ = try projectMemory?.writeKnownGoodPatternDraft(
            title: title,
            summary: summary,
            knowledgeClass: knowledgeClass,
            affectedModules: affectedModules,
            evidenceRefs: evidenceRefs,
            sourceTraceIDs: sourceTraceIDs,
            body: body
        )
    }

    public func recordRejectedApproach(
        title: String,
        summary: String,
        knowledgeClass: KnowledgeClass,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = [],
        body: String
    ) throws {
        _ = try projectMemory?.writeRejectedApproachDraft(
            title: title,
            summary: summary,
            knowledgeClass: knowledgeClass,
            affectedModules: affectedModules,
            evidenceRefs: evidenceRefs,
            sourceTraceIDs: sourceTraceIDs,
            body: body
        )
    }

    // MARK: - Memory Query Wrappers

    public func controlsForApp(_ app: String) -> [KnownControl] {
        appMemory.controlsForApp(app)
    }

    public func rankingBias(label: String?, app: String?) -> Double {
        executionStore.rankingBias(label: label, app: app)
    }

    public func commandBias(category: String?, workspaceRoot: String?) -> Double {
        patternStore.commandBias(category: category, workspaceRoot: workspaceRoot)
    }

    public func preferredFixPath(errorSignature: String?) -> String? {
        patternStore.preferredFixPath(errorSignature: errorSignature)
    }

    public func preferredRecoveryStrategy(app: String) -> String? {
        executionStore.preferredRecoveryStrategy(app: app)
    }
}
