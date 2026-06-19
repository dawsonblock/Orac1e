import Foundation
import Testing
@testable import OracleOS

@Suite("System Intelligence Upgrades")
struct SystemIntelligenceUpgradeTests {

    // MARK: - Phase 1: Plan Candidate enrichment

    @Test("Plan candidate computes estimated cost from operators")
    func planCandidateEstimatesCost() {
        let ops = [Operator(kind: .runTests), Operator(kind: .applyPatch)]
        let state = minimalReasoningState(agentKind: .code, repoOpen: true)
        let candidate = PlanCandidate(operators: ops, projectedState: state)

        #expect(candidate.estimatedCost > 0)
        #expect(candidate.estimatedCost == ops.reduce(0.0) { $0 + $1.baseCost })
    }

    @Test("Plan candidate computes average risk score from operators")
    func planCandidateComputesRiskScore() {
        let ops = [Operator(kind: .runTests), Operator(kind: .applyPatch)]
        let state = minimalReasoningState(agentKind: .code, repoOpen: true)
        let candidate = PlanCandidate(operators: ops, projectedState: state)

        let expectedRisk = ops.reduce(0.0) { $0 + $1.risk } / Double(ops.count)
        #expect(candidate.riskScore == expectedRisk)
    }

    @Test("Plan candidate with simulated outcome inherits success probability")
    func planCandidateInheritsSuccessProbability() {
        let ops = [Operator(kind: .dismissModal)]
        let state = minimalReasoningState(agentKind: .os, modalPresent: true)
        let simulated = SimulatedOutcome(
            successProbability: 0.85,
            estimatedSteps: 1,
            riskScore: 0.05
        )
        let candidate = PlanCandidate(
            operators: ops,
            projectedState: state,
            simulatedOutcome: simulated
        )

        #expect(candidate.successProbability == 0.85)
    }

    // MARK: - Phase 1: Recovery operators

    @Test("Recovery operators are available in the operator registry")
    func recoveryOperatorsAvailable() {
        let registry = OperatorRegistry()
        let state = minimalReasoningState(
            agentKind: .os,
            targetApplication: "Safari",
            activeApplication: "Finder",
            modalPresent: false
        )
        let available = registry.available(for: state)
        let kinds = available.map(\.kind)

        #expect(kinds.contains(.focusWindow))
        #expect(kinds.contains(.openApplication))
    }

    @Test("New failure classes exist")
    func newFailureClassesExist() {
        let classes: [FailureClass] = [
            .targetMissing,
            .permissionBlocked,
            .unexpectedDialog,
            .environmentMismatch,
        ]
        #expect(classes.count == 4)
        #expect(FailureClass.targetMissing.rawValue == "targetMissing")
    }


    // MARK: - Phase 2: Workflow confidence model

    @Test("Workflow confidence model scores promoted workflows higher")
    func workflowConfidenceScoresPromotedHigher() {
        let model = WorkflowConfidenceModel()
        let highConfidence = WorkflowPlan(
            agentKind: .os,
            goalPattern: "test",
            steps: [],
            successRate: 0.95,
            repeatedTraceSegmentCount: 8,
            replayValidationSuccess: 0.9,
            promotionStatus: .promoted,
            lastSucceededAt: Date()
        )
        let lowConfidence = WorkflowPlan(
            agentKind: .os,
            goalPattern: "test",
            steps: [],
            successRate: 0.3,
            repeatedTraceSegmentCount: 1,
            replayValidationSuccess: 0.2,
            promotionStatus: .candidate
        )

        let high = model.confidence(for: highConfidence)
        let low = model.confidence(for: lowConfidence)

        #expect(high.score > low.score)
    }

    @Test("Workflow confidence model reliability check")
    func workflowConfidenceReliabilityCheck() {
        let model = WorkflowConfidenceModel()
        let reliable = WorkflowPlan(
            agentKind: .os,
            goalPattern: "test",
            steps: [],
            successRate: 0.9,
            repeatedTraceSegmentCount: 10,
            replayValidationSuccess: 0.8,
            promotionStatus: .promoted,
            lastSucceededAt: Date()
        )

        #expect(model.isReliable(reliable))
    }

    // MARK: - Phase 3: Trace compressor

    @Test("Trace compressor groups events into patterns")
    func traceCompressorGroupsEvents() {
        let compressor = TraceCompressor()
        let events = [
            TraceEvent(action: "click", success: true, message: nil),
            TraceEvent(action: "click", success: true, message: nil),
            TraceEvent(action: "type", success: false, message: nil),
        ]
        let patterns = compressor.compress(events: events)

        #expect(!patterns.isEmpty)
        #expect(patterns.contains(where: { $0.actionName == "click" }))
    }

    @Test("Trace compressor computes success rate")
    func traceCompressorComputesSuccessRate() {
        let compressor = TraceCompressor()
        let patterns = [
            CompressedTracePattern(
                stateFingerprint: "state1",
                actionName: "click",
                resultSuccess: true,
                occurrences: 8,
                averageElapsedMs: 100
            ),
            CompressedTracePattern(
                stateFingerprint: "state2",
                actionName: "type",
                resultSuccess: false,
                occurrences: 2,
                averageElapsedMs: 50
            ),
        ]
        let rate = compressor.successRate(for: patterns)
        #expect(rate == 0.8)
    }

    // MARK: - Phase 3: Trace clusterer

    @Test("Trace clusterer groups similar traces")
    func traceClustererGroupsSimilar() {
        let clusterer = TraceClusterer(minimumClusterSize: 2, minimumSimilarity: 0.5)
        let trace1 = [
            TraceEvent(action: "click", success: true, message: nil),
            TraceEvent(action: "type", success: true, message: nil),
        ]
        let trace2 = [
            TraceEvent(action: "click", success: true, message: nil),
            TraceEvent(action: "type", success: true, message: nil),
        ]
        let trace3 = [
            TraceEvent(action: "navigate", success: true, message: nil),
        ]
        let clusters = clusterer.cluster(traces: [trace1, trace2, trace3])

        #expect(!clusters.isEmpty)
        #expect(clusters[0].traces.count == 2)
    }

    // MARK: - Phase 4: Recovery planner

    @Test("Recovery planner generates plans for modal blocking")
    func recoveryPlannerHandlesModal() {
        let planner = MainPlanner()
        let state = minimalReasoningState(agentKind: .os, modalPresent: true)
        let plans = planner.plan(failure: .modalBlocking, state: state)

        #expect(!plans.isEmpty)
        #expect(plans[0].recoveryOperators.contains(where: { $0.kind == .dismissModal }))
    }

    @Test("Recovery planner generates plans for wrong focus")
    func recoveryPlannerHandlesWrongFocus() {
        let planner = MainPlanner()
        let state = minimalReasoningState(
            agentKind: .os,
            targetApplication: "Safari",
            activeApplication: "Finder"
        )
        let plans = planner.plan(failure: .wrongFocus, state: state)

        #expect(!plans.isEmpty)
        #expect(plans[0].recoveryOperators.contains(where: { $0.kind == .focusWindow }))
    }

    @Test("Recovery planner generates plans for patch failure")
    func recoveryPlannerHandlesPatchFailure() {
        let planner = MainPlanner()
        let state = minimalReasoningState(agentKind: .code, repoOpen: true, patchApplied: true)
        let plans = planner.plan(failure: .patchApplyFailed, state: state)

        #expect(!plans.isEmpty)
        #expect(plans[0].recoveryOperators.contains(where: { $0.kind == .rollbackPatch || $0.kind == .revertPatch }))
    }

    // MARK: - Phase 5: Patch strategy library

    @Test("Patch strategy library returns applicable strategies")
    func patchStrategyLibraryReturnsApplicable() {
        let library = PatchStrategyLibrary.shared
        let strategies = library.applicable(for: "unexpectedly found nil while unwrapping", snapshot: nil)

        #expect(!strategies.isEmpty)
        #expect(strategies.contains(where: { $0.kind == .nullGuard }))
    }

    @Test("Patch strategy library covers all strategy kinds")
    func patchStrategyLibraryCoversAllKinds() {
        let library = PatchStrategyLibrary.shared
        for kind in PatchStrategyKind.allCases {
            #expect(library.strategy(for: kind) != nil)
        }
    }

    @Test("Patch ranking signals compute composite score")
    func patchRankingSignalsCompositeScore() {
        let signals = PatchRankingSignals(
            faultLocationConfidence: 0.8,
            patchComplexity: 0.3,
            coverageImpact: 0.6,
            memorySuccessPatterns: 0.5
        )
        #expect(signals.compositeScore > 0)
        #expect(signals.compositeScore <= 1.0)
    }

    // MARK: - Phase 6: Browser target scoring

    @Test("Browser target score computes weighted total")
    func browserTargetScoreComputation() {
        let score = BrowserTargetScore(
            textSimilarity: 0.9,
            roleMatch: 1.0,
            visibilityScore: 1.0,
            historicalSuccess: 0.5
        )
        #expect(score.totalScore > 0.7)
        #expect(score.totalScore <= 1.0)
    }

    // MARK: - Phase 6: Page element index enrichment

    @Test("Page element index provides enriched elements")
    func pageElementIndexEnrichedElements() {
        let enriched = PageElementAttributes(
            index: 1,
            role: "AXButton",
            label: "Submit",
            isClickable: true,
            isVisible: true,
            semanticLabel: "Submit"
        )
        #expect(enriched.isClickable)
        #expect(enriched.semanticLabel == "Submit")
    }

    // MARK: - Phase 5: Candidate patch with strategy

    @Test("Candidate patch supports strategy kind field")
    func candidatePatchSupportsStrategy() {
        let patch = CandidatePatch(
            title: "Fix nil crash",
            summary: "Add nil guard",
            workspaceRelativePath: "Sources/Foo.swift",
            content: "guard let x else { return }",
            strategyKind: PatchStrategyKind.nullGuard.rawValue,
            faultLocationConfidence: 0.85,
            complexity: 0.2
        )
        #expect(patch.strategyKind == "null_guard")
        #expect(patch.faultLocationConfidence == 0.85)
        #expect(patch.complexity == 0.2)
    }

    // MARK: - Phase 10: System dashboard

    @Test("System dashboard records and snapshots events")
    func systemDashboardRecordsEvents() {
        let dashboard = SystemDashboard()
        dashboard.recordAction("click_target")
        dashboard.recordAction("type_text")
        dashboard.recordRecovery(failure: "modalBlocking", strategy: "dismiss_modal")
        dashboard.recordWorkflowReuse(workflowID: "workflow-compose")
        dashboard.recordMemoryHit(query: "fix calculator", hitCount: 3)

        let snapshot = dashboard.snapshot()
        #expect(!snapshot.panels.isEmpty)
        #expect(snapshot.panels.contains(where: { $0.kind == .recentActions }))
        #expect(snapshot.panels.contains(where: { $0.kind == .recoveryEvents }))
        #expect(snapshot.panels.contains(where: { $0.kind == .workflowReuse }))
        #expect(snapshot.panels.contains(where: { $0.kind == .memoryHits }))
    }

    // MARK: - Integration

    @Test("Planner decision hierarchy prefers workflow over exploration")
    func plannerDecisionHierarchyPrefersWorkflow() {
        let workflowIndex = WorkflowIndex()
        workflowIndex.add(
            WorkflowPlan(
                id: "workflow-compose",
                agentKind: .os,
                goalPattern: "open compose",
                steps: [
                    WorkflowStep(
                        agentKind: .os,
                        stepPhase: .operatingSystem,
                        actionContract: ActionContract(
                            id: "compose-click",
                            skillName: "click",
                            targetRole: "AXButton",
                            targetLabel: "Compose",
                            locatorStrategy: "query"
                        ),
                        semanticQuery: ElementQuery(text: "Compose", clickable: true, visibleOnly: true, app: "Google Chrome"),
                        fromPlanningStateID: "chrome|gmail|browse"
                    ),
                ],
                successRate: 0.95,
                repeatedTraceSegmentCount: 4,
                replayValidationSuccess: 1.0,
                promotionStatus: .promoted
            )
        )
        let planner = MainPlanner(workflowIndex: workflowIndex, reasoningThreshold: 0)
        let goal = Goal(
            description: "open compose in gmail",
            targetApp: "Google Chrome",
            targetDomain: "mail.google.com",
            targetTaskPhase: "compose",
            preferredAgentKind: .os
        )
        planner.setGoal(goal)

        let worldState = WorldState(
            observationHash: "gmail-browse",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "chrome|gmail|browse"),
                clusterKey: StateClusterKey(rawValue: "chrome|gmail|browse"),
                appID: "Google Chrome",
                domain: "mail.google.com",
                windowClass: nil,
                taskPhase: "browse",
                focusedRole: nil,
                modalClass: nil,
                navigationClass: nil,
                controlContext: nil
            ),
            observation: Observation(
                app: "Google Chrome",
                windowTitle: "Inbox - Gmail",
                url: "https://mail.google.com/mail/u/0/#inbox",
                focusedElementID: nil,
                elements: [
                    UnifiedElement(id: "compose", source: .ax, role: "AXButton", label: "Compose", confidence: 0.95),
                ]
            )
        )

        let decision = planner.nextStep(
            worldState: worldState,
            graphStore: GraphStore(databaseURL: makeTempGraphURL())
        )

        #expect(decision?.source == .workflow)
    }

    // MARK: - Helpers

    private func minimalReasoningState(
        agentKind: AgentKind,
        repoOpen: Bool = false,
        patchApplied: Bool = false,
        targetApplication: String? = nil,
        activeApplication: String? = nil,
        modalPresent: Bool = false,
        visibleTargets: [String] = []
    ) -> ReasoningPlanningState {
        var state = ReasoningPlanningState(
            taskContext: TaskContext(
                goal: Goal(description: "test goal", preferredAgentKind: agentKind),
                agentKind: agentKind,
                workspaceRoot: repoOpen ? "/tmp/workspace" : nil,
                phases: [.operatingSystem]
            ),
            worldState: WorldState(
                observationHash: "test",
                planningState: PlanningState(
                    id: PlanningStateID(rawValue: "test"),
                    clusterKey: StateClusterKey(rawValue: "test"),
                    appID: activeApplication ?? "Test",
                    domain: nil,
                    windowClass: nil,
                    taskPhase: "test",
                    focusedRole: nil,
                    modalClass: modalPresent ? "dialog" : nil,
                    navigationClass: nil,
                    controlContext: nil
                ),
                observation: Observation(
                    app: activeApplication ?? "Test",
                    windowTitle: "Test",
                    url: nil,
                    focusedElementID: nil,
                    elements: modalPresent
                        ? [UnifiedElement(id: "dialog", source: .ax, role: "AXDialog", label: "Dialog", confidence: 0.9)]
                        : visibleTargets.map { UnifiedElement(id: $0, source: .ax, role: "AXButton", label: $0, confidence: 0.9) }
                ),
                repositorySnapshot: repoOpen
                    ? RepositorySnapshot(
                        id: "repo",
                        workspaceRoot: "/tmp/workspace",
                        buildTool: .swiftPackage,
                        files: [RepositoryFile(path: "Sources/Foo.swift", isDirectory: false)],
                        symbolGraph: SymbolGraph(),
                        dependencyGraph: DependencyGraph(),
                        testGraph: TestGraph(),
                        activeBranch: "main",
                        isGitDirty: true
                    )
                    : nil
            ),
            memoryInfluence: MemoryInfluence(
                preferredFixPath: repoOpen ? "Sources/Foo.swift" : nil
            )
        )
        state.targetApplication = targetApplication
        state.patchApplied = patchApplied
        return state
    }

    private func makeTempGraphURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("graph.sqlite3", isDirectory: false)
    }
}
