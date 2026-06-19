import Foundation

public final class CodePlanner: @unchecked Sendable {
    public let maxPatchIterations: Int
    public let maxBuildAttempts: Int
    public let maxTestAttempts: Int
    public let directRepairThreshold: Double
    private let repositoryIndexer: RepositoryIndexer
    private let codeQueryEngine: CodeQueryEngine
    private let impactAnalyzer: RepositoryChangeImpactAnalyzer
    private let architectureEngine: ArchitectureEngine
    private let graphPlanner: GraphPlanner
    private let workflowIndex: WorkflowIndex
    private let workflowRetriever: WorkflowRetriever
    private let workflowExecutor: WorkflowExecutor
    private let promptEngine: PromptEngine

    public init(
        maxPatchIterations: Int = 5,
        maxBuildAttempts: Int = 5,
        maxTestAttempts: Int = 5,
        directRepairThreshold: Double = 0.7,
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        codeQueryEngine: CodeQueryEngine = CodeQueryEngine(),
        impactAnalyzer: RepositoryChangeImpactAnalyzer = RepositoryChangeImpactAnalyzer(),
        architectureEngine: ArchitectureEngine = ArchitectureEngine(),
        graphPlanner: GraphPlanner = GraphPlanner(),
        workflowIndex: WorkflowIndex = WorkflowIndex(),
        workflowRetriever: WorkflowRetriever = WorkflowRetriever(),
        workflowExecutor: WorkflowExecutor = WorkflowExecutor(),
        promptEngine: PromptEngine = PromptEngine()
    ) {
        self.maxPatchIterations = maxPatchIterations
        self.maxBuildAttempts = maxBuildAttempts
        self.maxTestAttempts = maxTestAttempts
        self.directRepairThreshold = directRepairThreshold
        self.repositoryIndexer = repositoryIndexer
        self.codeQueryEngine = codeQueryEngine
        self.impactAnalyzer = impactAnalyzer
        self.architectureEngine = architectureEngine
        self.graphPlanner = graphPlanner
        self.workflowIndex = workflowIndex
        self.workflowRetriever = workflowRetriever
        self.workflowExecutor = workflowExecutor
        self.promptEngine = promptEngine
    }

    public func nextStep(
        taskContext: TaskContext,
        worldState: WorldState,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        selectedStrategy: SelectedStrategy
    ) -> PlannerDecision? {
        guard let workspaceRoot = taskContext.workspaceRoot else { return nil }
        let snapshot = worldState.repositorySnapshot
            ?? repositoryIndexer.indexIfNeeded(workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
        let enrichedWorldState = WorldState(
            observationHash: worldState.observationHash,
            planningState: worldState.planningState,
            beliefStateID: worldState.beliefStateID,
            observation: worldState.observation,
            repositorySnapshot: snapshot,
            lastAction: worldState.lastAction
        )
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: enrichedWorldState,
                errorSignature: taskContext.goal.description
            )
        )
        let description = taskContext.goal.description.lowercased()
        let projectMemorySignals = memoryInfluence.projectMemorySignals
        let candidatePaths = likelyCandidatePaths(
            taskContext: taskContext,
            snapshot: snapshot,
            memoryInfluence: memoryInfluence
        )
        let isRepairGoal = repairGoal(description)
        let projectMemoryRefs = projectMemorySignals.refs
        let projectMemoryContext = ProjectMemoryPlanningContext(refs: projectMemoryRefs)
        let architectureReview = architectureEngine.review(
            goalDescription: taskContext.goal.description,
            snapshot: snapshot,
            candidatePaths: candidatePaths
        )
        let explorationFallbackReason = "workflow retrieval, stable graph path reuse, and candidate graph reuse were unavailable"

        if let workflowDecision = workflowDecision(
            taskContext: taskContext,
            worldState: worldState,
            projectMemoryRefs: projectMemoryRefs,
            memoryStore: memoryStore,
            selectedStrategy: selectedStrategy
        ) {
            return workflowDecision
        }

        if let graphDecision = graphDecision(
            taskContext: taskContext,
            worldState: worldState,
            snapshot: snapshot,
            graphStore: graphStore,
            memoryStore: memoryStore,
            projectMemoryRefs: projectMemoryRefs,
            projectMemorySignals: projectMemorySignals,
            architectureReview: architectureReview
        ) {
            return graphDecision
        }

        if isRepairGoal,
           let repairDecision = repairDecision(
               taskContext: taskContext,
               worldState: worldState,
               snapshot: snapshot,
               projectMemoryRefs: projectMemoryRefs,
               projectMemoryContext: projectMemoryContext,
               projectMemorySignals: projectMemorySignals,
               memoryInfluence: memoryInfluence,
               architectureReview: architectureReview,
               candidatePaths: candidatePaths
           ) {
            return repairDecision
        }

        if description.contains("push") {
            return decision(
                taskContext: taskContext,
                worldState: worldState,
                for: "git_push",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason,
                notes: ["git push requested"] + projectMemorySignals.riskSummaries
            )
        }
        if description.contains("commit") {
            return decision(
                taskContext: taskContext,
                worldState: worldState,
                for: "git_commit",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        if description.contains("branch") {
            return decision(
                taskContext: taskContext,
                worldState: worldState,
                for: "git_branch",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        if description.contains("format") {
            return decision(
                taskContext: taskContext,
                worldState: worldState,
                for: "run_formatter",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        if description.contains("lint") {
            return decision(
                taskContext: taskContext,
                worldState: worldState,
                for: "run_linter",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        if description.contains("build") || description.contains("compile") {
            return decision(
                taskContext: taskContext,
                worldState: worldState,
                for: "run_build",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        if description.contains("test") || description.contains("failing") {
            return decision(
                taskContext: taskContext,
                worldState: worldState,
                for: "run_tests",
                snapshot: snapshot,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                fallbackReason: explorationFallbackReason
            )
        }
        return decision(
            taskContext: taskContext,
            worldState: worldState,
            for: "read_repository",
            snapshot: snapshot,
            projectMemoryRefs: projectMemoryRefs,
            architectureReview: architectureReview,
            fallbackReason: explorationFallbackReason,
            notes: ["default repository inspection"] + projectMemorySignals.riskSummaries
        )
    }

    private func graphDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        snapshot: RepositorySnapshot,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        projectMemoryRefs: [ProjectMemoryRef],
        projectMemorySignals: ProjectMemoryPlanningSignals,
        architectureReview: ArchitectureReview
    ) -> PlannerDecision? {
        let graphGoal = Goal(
            description: taskContext.goal.description,
            targetApp: taskContext.goal.targetApp,
            targetDomain: taskContext.goal.targetDomain,
            targetTaskPhase: taskContext.goal.targetTaskPhase,
            workspaceRoot: taskContext.goal.workspaceRoot,
            preferredAgentKind: .code
        )
        guard let searchResult = graphPlanner.search(
            from: worldState.planningState,
            goal: graphGoal,
            graphStore: graphStore,
            memoryStore: memoryStore,
            worldState: worldState,
            riskPenalty: graphRiskPenalty(
                architectureReview: architectureReview,
                projectMemorySignals: projectMemorySignals
            )
        ),
              let edge = searchResult.edges.first,
              let contract = graphStore.actionContract(for: edge.actionContractID)
        else {
            return candidateGraphDecision(
                taskContext: taskContext,
                worldState: worldState,
                snapshot: snapshot,
                graphStore: graphStore,
                memoryStore: memoryStore,
                projectMemoryRefs: projectMemoryRefs,
                projectMemorySignals: projectMemorySignals,
                architectureReview: architectureReview
            )
        }

        let decision = PlannerDecision(
            agentKind: .code,
            plannerFamily: .code,
            stepPhase: .engineering,
            executionMode: .direct,
            actionContract: contract,
            source: .stableGraph,
            pathEdgeIDs: searchResult.edges.map(\.edgeID),
            currentEdgeID: edge.edgeID,
            fallbackReason: "workflow retrieval did not yield a reusable plan",
            graphSearchDiagnostics: searchResult.diagnostics,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            refactorProposalID: architectureReview.refactorProposal?.id,
            notes: graphNotes(
                prefix: searchResult.reachedGoal ? "stable graph path reaches engineering goal" : "stable graph path improves engineering state",
                diagnostics: searchResult.diagnostics
            )
        )
        return decision.with(promptDiagnostics: promptEngine.codeRepair(
            taskContext: taskContext,
            worldState: worldState,
            snapshot: snapshot,
            candidatePaths: [],
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            notes: decision.notes,
            executionMode: .direct
        ).diagnostics)
    }

    private func candidateGraphDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        snapshot: RepositorySnapshot,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        projectMemoryRefs: [ProjectMemoryRef],
        projectMemorySignals: ProjectMemoryPlanningSignals,
        architectureReview: ArchitectureReview
    ) -> PlannerDecision? {
        let graphGoal = Goal(
            description: taskContext.goal.description,
            targetApp: taskContext.goal.targetApp,
            targetDomain: taskContext.goal.targetDomain,
            targetTaskPhase: taskContext.goal.targetTaskPhase,
            workspaceRoot: taskContext.goal.workspaceRoot,
            preferredAgentKind: .code
        )

        guard let selection = graphPlanner.bestCandidateEdge(
            from: worldState.planningState,
            goal: graphGoal,
            graphStore: graphStore,
            memoryStore: memoryStore,
            worldState: worldState,
            riskPenalty: graphRiskPenalty(
                architectureReview: architectureReview,
                projectMemorySignals: projectMemorySignals
            )
        ),
        let contract = selection.actionContract
        else {
            return nil
        }

        let decision = PlannerDecision(
            agentKind: .code,
            plannerFamily: .code,
            stepPhase: .engineering,
            executionMode: .direct,
            actionContract: contract,
            source: .candidateGraph,
            pathEdgeIDs: [selection.edge.edgeID],
            currentEdgeID: selection.edge.edgeID,
            fallbackReason: "workflow retrieval and stable graph path reuse were unavailable",
            graphSearchDiagnostics: selection.diagnostics,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            refactorProposalID: architectureReview.refactorProposal?.id,
            notes: graphNotes(
                prefix: "candidate graph edge reuse",
                diagnostics: selection.diagnostics
            ) + ["candidate score \(String(format: "%.2f", selection.score))"]
        )
        return decision.with(promptDiagnostics: promptEngine.codeRepair(
            taskContext: taskContext,
            worldState: worldState,
            snapshot: snapshot,
            candidatePaths: [],
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            notes: decision.notes,
            executionMode: .direct
        ).diagnostics)
    }

    private func workflowDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        projectMemoryRefs: [ProjectMemoryRef],
        memoryStore: UnifiedMemoryStore,
        selectedStrategy: SelectedStrategy
    ) -> PlannerDecision? {
        guard let workflowMatch = workflowRetriever.retrieve(
            goal: taskContext.goal,
            taskContext: taskContext,
            worldState: worldState,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore,
            selectedStrategy: selectedStrategy
        ) else {
            return nil
        }
        let decision = workflowExecutor.nextDecision(
            match: workflowMatch,
            plannerFamily: .code,
            sourceNotes: projectMemoryRefs.isEmpty ? [] : ["project memory informed workflow retrieval"]
        )
        return decision.with(promptDiagnostics: promptEngine.workflowSelection(
            goal: taskContext.goal,
            taskContext: taskContext,
            worldState: worldState,
            match: workflowMatch
        ).diagnostics)
    }

    private func decision(
        taskContext: TaskContext,
        worldState: WorldState,
        for skillName: String,
        snapshot: RepositorySnapshot,
        workspaceRelativePath: String? = nil,
        projectMemoryRefs: [ProjectMemoryRef] = [],
        architectureReview: ArchitectureReview = ArchitectureReview(
            triggered: false,
            affectedModules: [],
            findings: [],
            refactorProposal: nil,
            riskScore: 0
        ),
        executionMode: PlannerExecutionMode = .direct,
        experimentSpec: ExperimentSpec? = nil,
        experimentDecision: ExperimentDecision? = nil,
        fallbackReason: String? = nil,
        candidatePaths: [String] = [],
        notes: [String] = ["bounded code exploration"]
    ) -> PlannerDecision? {
        let contract = ActionContract(
            id: [
                "code",
                skillName,
                snapshot.buildTool.rawValue,
                snapshot.activeBranch ?? "detached",
                workspaceRelativePath ?? "none",
            ].joined(separator: "|"),
            agentKind: .code,
            skillName: skillName,
            targetRole: nil,
            targetLabel: nil,
            locatorStrategy: "code-planner",
            workspaceRelativePath: workspaceRelativePath,
            commandCategory: commandCategory(for: skillName)?.rawValue,
            plannerFamily: PlannerFamily.code.rawValue
        )
        let promptDiagnostics = promptEngine.codeRepair(
            taskContext: taskContext,
            worldState: worldState,
            snapshot: snapshot,
            candidatePaths: candidatePaths.isEmpty ? [workspaceRelativePath].compactMap { $0 } : candidatePaths,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            notes: notes,
            executionMode: executionMode
        ).diagnostics
        return PlannerDecision(
            agentKind: .code,
            skillName: skillName,
            plannerFamily: .code,
            stepPhase: .engineering,
            executionMode: executionMode,
            actionContract: contract,
            source: .exploration,
            fallbackReason: fallbackReason,
            projectMemoryRefs: projectMemoryRefs,
            architectureFindings: architectureReview.findings,
            refactorProposalID: architectureReview.refactorProposal?.id,
            experimentSpec: experimentSpec,
            experimentDecision: experimentDecision,
            notes: notes,
            promptDiagnostics: promptDiagnostics
        )
    }

    private func repairDecision(
        taskContext: TaskContext,
        worldState: WorldState,
        snapshot: RepositorySnapshot,
        projectMemoryRefs: [ProjectMemoryRef],
        projectMemoryContext: ProjectMemoryPlanningContext,
        projectMemorySignals: ProjectMemoryPlanningSignals,
        memoryInfluence: MemoryInfluence,
        architectureReview: ArchitectureReview,
        candidatePaths: [String]
    ) -> PlannerDecision? {
        let assessment = assessRepairRouting(
            taskContext: taskContext,
            snapshot: snapshot,
            architectureReview: architectureReview,
            projectMemoryContext: projectMemoryContext,
            projectMemorySignals: projectMemorySignals,
            memoryInfluence: memoryInfluence,
            candidatePaths: candidatePaths
        )

        if assessment.shouldUseExperiments,
           let experimentSpec = experimentSpec(
               taskContext: taskContext,
               snapshot: snapshot,
               architectureReview: architectureReview,
               candidatePaths: candidatePaths,
               assessment: assessment
           ) {
            let primaryPath = experimentSpec.candidates.first?.workspaceRelativePath
            let experimentDecision = ExperimentDecision(
                reason: assessment.experimentReason ?? "low-confidence repair path",
                candidateCount: experimentSpec.candidates.count,
                architectureRiskScore: architectureReview.riskScore
            )
            return decision(
                taskContext: taskContext,
                worldState: worldState,
                for: "generate_patch",
                snapshot: snapshot,
                workspaceRelativePath: primaryPath,
                projectMemoryRefs: projectMemoryRefs,
                architectureReview: architectureReview,
                executionMode: .experiment,
                experimentSpec: experimentSpec,
                experimentDecision: experimentDecision,
                fallbackReason: "workflow retrieval, stable graph path reuse, and candidate graph reuse were unavailable",
                candidatePaths: experimentSpec.candidates.map(\.workspaceRelativePath),
                notes: [
                    "parallel experiment fanout requested",
                    "direct repair confidence \(String(format: "%.2f", assessment.directRepairConfidence))",
                    "candidate count \(experimentSpec.candidates.count)",
                ] + assessment.reasons + projectMemorySignals.riskSummaries
            )
        }

        let preferredPath = candidatePaths.first
        let constrainedRefactor = taskContext.goal.description.lowercased().contains("refactor")
            && architectureReview.triggered
            && projectMemoryContext.hasArchitectureDecisions
        let skillName = constrainedRefactor ? "search_code" : (preferredPath == nil ? "search_code" : "edit_file")
        let targetNote = preferredPath.map { "memory/query-biased target \($0)" } ?? "code exploration fallback"
        return decision(
            taskContext: taskContext,
            worldState: worldState,
            for: skillName,
            snapshot: snapshot,
            workspaceRelativePath: preferredPath,
            projectMemoryRefs: projectMemoryRefs,
            architectureReview: architectureReview,
            fallbackReason: "workflow retrieval, stable graph path reuse, and candidate graph reuse were unavailable",
            candidatePaths: candidatePaths,
            notes: [
                targetNote,
                "direct repair confidence \(String(format: "%.2f", assessment.directRepairConfidence))",
            ] + assessment.reasons + projectMemorySignals.riskSummaries
        )
    }

    private func likelyCandidatePaths(
        taskContext: TaskContext,
        snapshot: RepositorySnapshot,
        memoryInfluence: MemoryInfluence
    ) -> [String] {
        var candidates: [String] = []
        if let preferredPath = memoryInfluence.preferredFixPath {
            candidates.append(preferredPath)
        }

        let likelyRootCauses = codeQueryEngine.findLikelyRootCause(
            failureDescription: taskContext.goal.description,
            in: snapshot,
            preferredPaths: Set(memoryInfluence.preferredPaths),
            avoidedPaths: Set(memoryInfluence.avoidedPaths)
        )
        candidates.append(contentsOf: likelyRootCauses.map(\.path))
        candidates.append(contentsOf: memoryInfluence.preferredPaths)

        if candidates.isEmpty {
            candidates.append(contentsOf: snapshot.files
                .filter { !$0.isDirectory && $0.path.hasSuffix(".swift") }
                .map(\.path)
                .prefix(3))
        }

        let preferredPaths = Set(memoryInfluence.preferredPaths)
        let avoidedPaths = Set(memoryInfluence.avoidedPaths)
        let ranked = impactAnalyzer.rankCandidates(
            orderedUnique(candidates),
            in: snapshot,
            preferredPaths: preferredPaths,
            avoidedPaths: avoidedPaths
        )
        let strongCandidates: [RankedCodeCandidate]
        if let topScore = ranked.first?.score {
            let threshold = max(0.35, topScore - 0.2)
            strongCandidates = ranked.filter { $0.score >= threshold }
        } else {
            strongCandidates = ranked
        }

        if let preferredPath = memoryInfluence.preferredFixPath,
           let preferredMatch = strongCandidates.first(where: { $0.path == preferredPath }),
           let topCandidate = strongCandidates.first,
           preferredMatch.score >= topCandidate.score - 0.1
        {
            return [preferredPath]
        }

        if let best = strongCandidates.first {
            let secondBestScore = strongCandidates.dropFirst().first?.score ?? 0
            let clearMargin = best.score - secondBestScore >= 0.15
            let preferredWinner = preferredPaths.contains(best.path)
                || memoryInfluence.preferredFixPath == best.path
            if preferredWinner && clearMargin {
                return [best.path]
            }
        }
        return Array(strongCandidates.prefix(3).map(\.path))
    }

    private func graphNotes(prefix: String, diagnostics: GraphSearchDiagnostics) -> [String] {
        var notes = [prefix, "explored \(diagnostics.exploredEdgeIDs.count) graph edges"]
        if !diagnostics.rejectedEdgeIDs.isEmpty {
            notes.append("rejected \(diagnostics.rejectedEdgeIDs.count) alternatives")
        }
        if let fallbackReason = diagnostics.fallbackReason {
            notes.append(fallbackReason)
        }
        return notes
    }

    private func experimentSpec(
        taskContext: TaskContext,
        snapshot: RepositorySnapshot,
        architectureReview: ArchitectureReview,
        candidatePaths: [String],
        assessment: RepairRoutingAssessment
    ) -> ExperimentSpec? {
        guard !taskContext.experimentCandidates.isEmpty else {
            return nil
        }

        guard assessment.shouldUseExperiments,
              let workspaceRoot = taskContext.workspaceRoot
        else {
            return nil
        }

        let workspaceURL = URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        let rankedCandidatePaths: [String]
        if candidatePaths.isEmpty == false {
            rankedCandidatePaths = Array(candidatePaths.prefix(2))
        } else {
            let searchScores = Dictionary(
                uniqueKeysWithValues: CodeSearch()
                    .search(query: taskContext.goal.description, in: snapshot)
                    .map { ($0.path, $0.score) }
            )
            let impactScores = Dictionary(
                uniqueKeysWithValues: impactAnalyzer.rankCandidates(
                    taskContext.experimentCandidates.map(\.workspaceRelativePath),
                    in: snapshot
                ).map { ($0.path, $0.score) }
            )
            rankedCandidatePaths = orderedUnique(taskContext.experimentCandidates.map(\.workspaceRelativePath)).sorted { lhs, rhs in
                let lhsScore = impactScores[lhs, default: 0] + searchScores[lhs, default: 0]
                let rhsScore = impactScores[rhs, default: 0] + searchScores[rhs, default: 0]
                if lhsScore == rhsScore {
                    return lhs < rhs
                }
                return lhsScore > rhsScore
            }
        }
        return ExperimentSpec(
            goalDescription: taskContext.goal.description,
            workspaceRoot: workspaceRoot,
            candidates: rankedExperimentCandidates(
                taskContext.experimentCandidates,
                candidatePaths: rankedCandidatePaths,
                maxCount: taskContext.maxExperimentCandidates
            ),
            buildCommand: BuildToolDetector.defaultBuildCommand(for: snapshot.buildTool, workspaceRoot: workspaceURL),
            testCommand: BuildToolDetector.defaultTestCommand(for: snapshot.buildTool, workspaceRoot: workspaceURL),
            promptDiagnostics: promptEngine.experimentGeneration(
                spec: ExperimentSpec(
                    goalDescription: taskContext.goal.description,
                    workspaceRoot: workspaceRoot,
                    candidates: rankedExperimentCandidates(
                        taskContext.experimentCandidates,
                        candidatePaths: rankedCandidatePaths,
                        maxCount: taskContext.maxExperimentCandidates
                    ),
                    buildCommand: BuildToolDetector.defaultBuildCommand(for: snapshot.buildTool, workspaceRoot: workspaceURL),
                    testCommand: BuildToolDetector.defaultTestCommand(for: snapshot.buildTool, workspaceRoot: workspaceURL)
                ),
                snapshot: snapshot
            ).diagnostics
        )
    }

    private func assessRepairRouting(
        taskContext: TaskContext,
        snapshot: RepositorySnapshot,
        architectureReview: ArchitectureReview,
        projectMemoryContext: ProjectMemoryPlanningContext,
        projectMemorySignals: ProjectMemoryPlanningSignals,
        memoryInfluence: MemoryInfluence,
        candidatePaths: [String]
    ) -> RepairRoutingAssessment {
        var confidence = 0.45
        var reasons: [String] = []
        let description = taskContext.goal.description.lowercased()
        let preferredPaths = Set(projectMemorySignals.preferredPaths(in: snapshot))
        let avoidedPaths = Set(projectMemorySignals.avoidedPaths(in: snapshot))
        let preferredCandidateCount = candidatePaths.filter { preferredPaths.contains($0) }.count
        let effectiveCandidateCount = preferredCandidateCount == 1 ? 1 : candidatePaths.count

        if effectiveCandidateCount == 1 {
            confidence += 0.25
            reasons.append(preferredCandidateCount == 1 ? "project memory narrowed to one likely target path" : "single likely target path")
        } else if effectiveCandidateCount > 1 {
            confidence -= 0.25
            reasons.append("multiple plausible target paths")
        } else {
            confidence -= 0.15
            reasons.append("no strong target path")
        }

        if projectMemoryContext.hasKnownGoodPatterns {
            confidence += 0.15
            reasons.append("known-good patterns favor direct repair")
        }
        if projectMemoryContext.hasArchitectureDecisions {
            confidence += 0.05
            reasons.append("architecture decisions constrain repair shape")
        }
        if candidatePaths.contains(where: { preferredPaths.contains($0) }) {
            confidence += 0.25
            reasons.append("known-good project memory narrowed the target path")
        }
        if description.contains(".swift") || description.contains(".ts") || description.contains(".js") || description.contains(".py") {
            confidence += 0.1
            reasons.append("goal names an explicit code file")
        }
        if projectMemoryContext.hasRejectedApproaches {
            confidence -= 0.2
            reasons.append("rejected approaches discourage single-path repair")
        }
        if candidatePaths.contains(where: { avoidedPaths.contains($0) }) {
            confidence -= 0.2
            reasons.append("project memory marks this repair path as previously rejected")
        }
        if projectMemoryContext.hasOpenProblems {
            confidence -= 0.15
            reasons.append("open problems suggest unresolved prior attempts")
        }
        if memoryInfluence.shouldPreferExperiments {
            confidence -= 0.1
            reasons.append("memory routing prefers experiment fanout")
        }
        if projectMemorySignals.hasRisks,
           description.contains("push") || description.contains("delete") || description.contains("release") {
            confidence -= 0.1
            reasons.append("risk register warns about this operation class")
        }
        if architectureReview.triggered || architectureReview.riskScore >= 0.5 {
            confidence -= 0.2
            reasons.append("architecture review raises repair risk")
        }
        if description.contains("compare") || description.contains("experiment") {
            confidence -= 0.1
            reasons.append("goal explicitly requests comparison")
        }

        confidence = min(max(confidence, 0), 1)

        let hasExperimentCandidates = !taskContext.experimentCandidates.isEmpty
        let architectureRequiresExperiment = architectureReview.riskScore >= 0.5 && preferredCandidateCount == 0
        let shouldUseExperiments = hasExperimentCandidates && (
            confidence < directRepairThreshold
                || effectiveCandidateCount > 1
                || projectMemoryContext.shouldEscalateToExperiment
                || memoryInfluence.shouldPreferExperiments
                || architectureRequiresExperiment
                || description.contains("compare")
                || description.contains("experiment")
        )

        let experimentReason: String?
        if shouldUseExperiments {
            if projectMemoryContext.hasRejectedApproaches {
                experimentReason = "previous approaches were rejected"
            } else if effectiveCandidateCount > 1 {
                experimentReason = "ambiguous edit target"
            } else if projectMemoryContext.hasOpenProblems {
                experimentReason = "open problem remains unresolved"
            } else if architectureRequiresExperiment {
                experimentReason = "architecture impact is high enough to compare fixes"
            } else {
                experimentReason = "direct repair confidence fell below threshold"
            }
        } else {
            experimentReason = nil
        }

        return RepairRoutingAssessment(
            directRepairConfidence: confidence,
            shouldUseExperiments: shouldUseExperiments,
            experimentReason: experimentReason,
            reasons: reasons
        )
    }

    private func repairGoal(_ description: String) -> Bool {
        description.contains("fix")
            || description.contains("patch")
            || description.contains("repair")
            || description.contains("refactor")
            || description.contains("failing")
            || description.contains("broken")
            || description.contains("error")
    }

    private func rankedExperimentCandidates(
        _ candidates: [CandidatePatch],
        candidatePaths: [String],
        maxCount: Int
    ) -> [CandidatePatch] {
        let order = Dictionary(uniqueKeysWithValues: candidatePaths.enumerated().map { ($1, $0) })
        let effectiveLimit = min(maxCount, max(1, min(2, candidatePaths.count)))
        let preferred = candidates.filter { order[$0.workspaceRelativePath] != nil }
            .sorted { lhs, rhs in
                let lhsRank = order[lhs.workspaceRelativePath] ?? .max
                let rhsRank = order[rhs.workspaceRelativePath] ?? .max
                if lhsRank == rhsRank {
                    return lhs.workspaceRelativePath < rhs.workspaceRelativePath
                }
                return lhsRank < rhsRank
            }
        if !preferred.isEmpty {
            return Array(preferred.prefix(effectiveLimit))
        }
        return Array(candidates.prefix(maxCount))
    }

    private func commandCategory(for skillName: String) -> CodeCommandCategory? {
        switch skillName {
        case "read_repository":
            .indexRepository
        case "search_code":
            .searchCode
        case "open_file":
            .openFile
        case "edit_file":
            .editFile
        case "write_file":
            .writeFile
        case "generate_patch":
            .generatePatch
        case "run_build":
            .build
        case "run_tests":
            .test
        case "run_formatter":
            .formatter
        case "run_linter":
            .linter
        case "git_status":
            .gitStatus
        case "git_branch":
            .gitBranch
        case "git_commit":
            .gitCommit
        case "git_push":
            .gitPush
        default:
            nil
        }
    }

    private func graphRiskPenalty(
        architectureReview: ArchitectureReview,
        projectMemorySignals: ProjectMemoryPlanningSignals
    ) -> Double {
        let architecturePenalty = architectureReview.riskScore * 0.15
        let projectMemoryPenalty = projectMemorySignals.hasRisks ? 0.1 : 0
        return min(0.25, architecturePenalty + projectMemoryPenalty)
    }

}

private struct RepairRoutingAssessment {
    let directRepairConfidence: Double
    let shouldUseExperiments: Bool
    let experimentReason: String?
    let reasons: [String]
}

private struct ProjectMemoryPlanningContext {
    let refs: [ProjectMemoryRef]

    var hasRejectedApproaches: Bool {
        refs.contains(where: { $0.kind == .rejectedApproach })
    }

    var hasKnownGoodPatterns: Bool {
        refs.contains(where: { $0.kind == .knownGoodPattern })
    }

    var hasOpenProblems: Bool {
        refs.contains(where: { $0.kind == .openProblem })
    }

    var hasArchitectureDecisions: Bool {
        refs.contains(where: { $0.kind == .architectureDecision })
    }

    var shouldEscalateToExperiment: Bool {
        hasRejectedApproaches || hasOpenProblems
    }

    var experimentBiasNote: String {
        if hasRejectedApproaches {
            return "rejected approaches bias toward experiment fanout"
        }
        if hasOpenProblems {
            return "open problems bias toward experiment fanout"
        }
        return "experiments available"
    }

    var planningBiasNote: String {
        if hasKnownGoodPatterns {
            return "known-good patterns increased direct repair preference"
        }
        if hasArchitectureDecisions {
            return "architecture decisions constrained repair path"
        }
        return "project memory context available"
    }
}

private func orderedUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
}
