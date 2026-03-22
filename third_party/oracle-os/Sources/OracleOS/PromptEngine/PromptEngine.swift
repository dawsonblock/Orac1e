import Foundation

public struct PromptPackage: Sendable, Equatable {
    public let document: PromptDocument
    public let diagnostics: PromptDiagnostics

    public init(document: PromptDocument, diagnostics: PromptDiagnostics) {
        self.document = document
        self.diagnostics = diagnostics
    }
}

public final class PromptEngine: @unchecked Sendable {
    private let registry: PromptTemplateRegistry
    private let assembler: ContextAssembler
    private let optimizer: QueryOptimizer
    private let validator: PromptValidator
    private let builder: PromptBuilder
    private let policy: PromptPolicy
    private let cache: PromptCache

    public init(
        registry: PromptTemplateRegistry = PromptTemplateRegistry(),
        assembler: ContextAssembler = ContextAssembler(),
        optimizer: QueryOptimizer = QueryOptimizer(),
        validator: PromptValidator = PromptValidator(),
        builder: PromptBuilder = PromptBuilder(),
        policy: PromptPolicy = PromptPolicy(),
        cache: PromptCache = .shared
    ) {
        self.registry = registry
        self.assembler = assembler
        self.optimizer = optimizer
        self.validator = validator
        self.builder = builder
        self.policy = policy
        self.cache = cache
    }

    public func planning(
        goal: Goal,
        taskContext: TaskContext,
        worldState: WorldState,
        selectedOperators: [String],
        candidatePlans: [ScoredPlanSummary],
        fallbackReason: String?,
        projectMemoryRefs: [ProjectMemoryRef],
        notes: [String]
    ) -> PromptPackage {
        let template = registry.template(for: .planning)
        let context = assembler.planning(
            goal: goal,
            taskContext: taskContext,
            worldState: worldState,
            selectedOperators: selectedOperators,
            candidatePlans: candidatePlans,
            fallbackReason: fallbackReason,
            projectMemoryRefs: projectMemoryRefs,
            notes: notes,
            template: template
        )
        return package(for: context)
    }

    public func workflowSelection(
        goal: Goal,
        taskContext: TaskContext,
        worldState: WorldState,
        match: WorkflowMatch
    ) -> PromptPackage {
        let template = registry.template(for: .workflowSelection)
        let context = assembler.workflowSelection(
            goal: goal,
            taskContext: taskContext,
            worldState: worldState,
            match: match,
            template: template
        )
        return package(for: context)
    }

    public func codeRepair(
        taskContext: TaskContext,
        worldState: WorldState,
        snapshot: RepositorySnapshot,
        candidatePaths: [String],
        projectMemoryRefs: [ProjectMemoryRef],
        architectureFindings: [ArchitectureFinding],
        notes: [String],
        executionMode: PlannerExecutionMode
    ) -> PromptPackage {
        let template = registry.template(for: .codeRepair)
        let context = assembler.codeRepair(
            taskContext: taskContext,
            worldState: worldState,
            snapshot: snapshot,
            candidatePaths: candidatePaths,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureFindings,
            notes: notes,
            executionMode: executionMode,
            template: template
        )
        return package(for: context)
    }

    public func osAction(
        goal: Goal,
        worldState: WorldState,
        actionContract: ActionContract,
        semanticQuery: ElementQuery?,
        source: PlannerSource,
        fallbackReason: String?,
        notes: [String]
    ) -> PromptPackage {
        let template = registry.template(for: .osAction)
        let context = assembler.osAction(
            goal: goal,
            worldState: worldState,
            actionContract: actionContract,
            semanticQuery: semanticQuery,
            source: source,
            fallbackReason: fallbackReason,
            notes: notes,
            template: template
        )
        return package(for: context)
    }

    public func experimentGeneration(
        spec: ExperimentSpec,
        snapshot: RepositorySnapshot?
    ) -> PromptPackage {
        let template = registry.template(for: .experimentGeneration)
        let context = assembler.experimentGeneration(
            spec: spec,
            snapshot: snapshot,
            template: template
        )
        return package(for: context)
    }

    public func recoverySelection(
        failure: FailureClass,
        state: WorldState,
        orderedStrategies: [String],
        preferredStrategy: String?
    ) -> PromptPackage {
        let template = registry.template(for: .recoverySelection)
        let context = assembler.recoverySelection(
            failure: failure,
            state: state,
            orderedStrategies: orderedStrategies,
            preferredStrategy: preferredStrategy,
            template: template
        )
        return package(for: context)
    }

    private func package(for rawContext: PromptContext) -> PromptPackage {
        let optimizedContext = optimizer.optimize(
            policy.enforce(on: rawContext)
        )
        let cacheKey = PromptCache.cacheKey(for: optimizedContext)
        if let cached = cache.document(for: cacheKey) {
            let validation = validator.validate(document: cached)
            return PromptPackage(
                document: cached,
                diagnostics: .build(
                    document: cached,
                    cacheKey: cacheKey,
                    cacheHit: true,
                    validation: validation
                )
            )
        }

        let document = builder.build(from: optimizedContext)
        let validation = validator.validate(document: document)
        cache.store(document, for: cacheKey)

        return PromptPackage(
            document: document,
            diagnostics: .build(
                document: document,
                cacheKey: cacheKey,
                cacheHit: false,
                validation: validation
            )
        )
    }
}
