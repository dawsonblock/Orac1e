import Foundation
import Testing
@testable import OracleOS

@Suite("Digital Engineer Layer")
struct DigitalEngineerLayerTests {

    @Test("Project memory drafts are indexed and retrieved by goal and module")
    func projectMemoryDraftsAreQueryable() throws {
        let projectRoot = makeTempDirectory()
        let store = try ProjectMemoryStore(projectRootURL: projectRoot)

        let draftRef = try store.writeArchitectureDecisionDraft(
            title: "Use graph-backed planner",
            summary: "Prefer verified transitions over direct planner heuristics.",
            knowledgeClass: .reusable,
            affectedModules: ["Agent/Planning", "Graph"],
            evidenceRefs: ["trace:graph-backed-loop"],
            sourceTraceIDs: ["trace-graph-1"],
            body: "Decision: use graph-backed planning to keep execution reusable and safe."
        )

        let snapshot = RepositorySnapshot(
            id: "repo-snapshot",
            workspaceRoot: projectRoot.path,
            buildTool: .swiftPackage,
            files: [
                RepositoryFile(path: "Sources/OracleOS/Planning/MainPlanner.swift", isDirectory: false),
                RepositoryFile(path: "Sources/OracleOS/WorldModel/Graph/GraphStore.swift", isDirectory: false),
            ],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: false
        )

        let refs = ProjectMemoryQuery.relevantRecords(
            goalDescription: "graph-backed planner",
            snapshot: snapshot,
            store: store
        )

        #expect(refs.contains(where: { $0.id == draftRef.id }))
        #expect(refs.contains(where: { $0.affectedModules.contains("Agent/Planning") }))
    }

    @Test("Project memory query exposes typed planning records")
    func projectMemoryQueryExposesTypedRecords() throws {
        let workspace = try makeCodePlannerWorkspace()
        let store = try ProjectMemoryStore(projectRootURL: workspace.root)
        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace.root)

        _ = try store.writeKnownGoodPatternDraft(
            title: "Known good calculator fix",
            summary: "Restoring Sources/Example/Calculator.swift is a reliable fix.",
            knowledgeClass: .reusable,
            affectedModules: ["Sources/Example"],
            body: "Prefer Sources/Example/Calculator.swift for repeated repair tasks."
        )
        _ = try store.writeRejectedApproachDraft(
            title: "Do not rewrite CalculatorTests first",
            summary: "Editing Tests/ExampleTests/CalculatorTests.swift first delayed repair.",
            knowledgeClass: .reusable,
            affectedModules: ["Tests/ExampleTests"],
            body: "Avoid touching Tests/ExampleTests/CalculatorTests.swift before the source fix."
        )
        _ = try store.writeArchitectureDecisionDraft(
            title: "Keep calculator logic in source target",
            summary: "Architecture keeps business logic in Sources/Example/Calculator.swift.",
            knowledgeClass: .reusable,
            affectedModules: ["Sources/Example"],
            body: "Do not move this behavior into tests."
        )
        _ = try store.writeRiskDraft(
            title: "Release operations require extra care",
            summary: "Release and push operations are risky in this workspace.",
            knowledgeClass: .reusable,
            affectedModules: ["Sources/Example"],
            body: "Treat push and release steps as risky."
        )

        let signals = ProjectMemoryQuery.planningSignals(
            goalDescription: "fix failing build in Sources/Example/Calculator.swift and avoid risky release",
            snapshot: snapshot,
            store: store
        )

        #expect(signals.knownGoodPatterns.count == 1)
        #expect(signals.rejectedApproaches.count == 1)
        #expect(signals.architectureDecisions.count == 1)
        #expect(signals.risks.count == 1)
        #expect(signals.preferredPaths(in: snapshot).contains("Sources/Example/Calculator.swift"))
        #expect(signals.avoidedPaths(in: snapshot).contains("Tests/ExampleTests/CalculatorTests.swift"))
    }

    @Test("Memory router combines project memory and fix patterns for code planning")
    func memoryRouterCombinesProjectAndPatternMemory() throws {
        let workspace = try makeCodePlannerWorkspace()
        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace.root)
        let taskContext = TaskContext.from(
            goal: Goal(
                description: "fix failing build in Sources/Example/Calculator.swift",
                workspaceRoot: workspace.root.path,
                preferredAgentKind: .code
            ),
            workspaceRoot: workspace.root
        )
        let worldState = WorldState(
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: snapshot
        )

        let projectMemoryStore = try ProjectMemoryStore(projectRootURL: workspace.root)
        _ = try projectMemoryStore.writeKnownGoodPatternDraft(
            title: "Calculator source repair is reliable",
            summary: "Prefer Sources/Example/Calculator.swift for repeated calculator repair.",
            knowledgeClass: .reusable,
            affectedModules: ["Sources/Example"],
            body: "Prefer Sources/Example/Calculator.swift when calculator repair is requested."
        )

        let memoryStore = UnifiedMemoryStore()
        memoryStore.setWorkspaceRoot(workspace.root.path)
        for _ in 0..<3 {
            memoryStore.recordFixPattern(
                FixPattern(
                    errorSignature: taskContext.goal.description,
                    workspaceRelativePath: "Sources/Example/Calculator.swift",
                    commandCategory: CodeCommandCategory.editFile.rawValue
                ),
                success: true
            )
        }

        let influence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(
                taskContext: taskContext,
                worldState: worldState,
                errorSignature: taskContext.goal.description
            )
        )

        #expect(influence.preferredFixPath == "Sources/Example/Calculator.swift")
        #expect(influence.preferredPaths.contains("Sources/Example/Calculator.swift"))
        #expect(influence.projectMemoryRefs.contains(where: { $0.kind == .knownGoodPattern }))
        #expect(influence.notes.contains(where: { $0.contains("project memory") }))
    }

    @Test("Execution memory biases target ranking after repeated success")
    func executionMemoryBiasesTargetRanking() {
        let store = UnifiedMemoryStore()
        for _ in 0..<3 {
            store.recordControl(
                KnownControl(
                    key: "Finder|Open",
                    app: "Finder",
                    label: "Open",
                    role: "button",
                    elementID: "open-primary",
                    successCount: 1
                )
            )
        }

        let router = MemoryRouter(memoryStore: store)
        let bias = router.rankingBias(label: "Open", app: "Finder")

        #expect(bias > 0)
    }

    @MainActor
    @Test("Recovery selector prefers remembered successful strategy")
    func recoverySelectorPrefersRememberedSuccessfulStrategy() {
        let registry = RecoveryRegistry.live()
        let selector = RecoveryStrategySelector(registry: registry)
        let memoryStore = UnifiedMemoryStore()
        memoryStore.recordStrategy(
            StrategyRecord(app: "Safari", strategy: "dismiss_modal", success: true)
        )

        let state = WorldState(
            observation: Observation(app: "Safari", windowTitle: "Inbox", url: nil, focusedElementID: nil, elements: [])
        )

        let ordered = selector.orderedStrategies(
            for: .modalBlocking,
            state: state,
            memoryStore: memoryStore
        )

        #expect(ordered.first?.name == "dismiss_modal")
    }

    @MainActor
    @Test("Recovery engine attaches prompt diagnostics to recovery attempts")
    func recoveryEngineAttachesPromptDiagnostics() async {
        let engine = RecoveryEngine()
        let attempt = await engine.recover(
            failure: .modalBlocking,
            state: WorldState(
                observation: Observation(app: "Safari", windowTitle: "Inbox", url: nil, focusedElementID: nil, elements: [])
            ),
            memoryStore: UnifiedMemoryStore()
        )

        #expect(attempt.promptDiagnostics?.templateKind == .recoverySelection)
    }

    @Test("Architecture engine emits cycle and boundary findings")
    func architectureEngineEmitsFindings() {
        let engine = ArchitectureEngine()
        let snapshot = RepositorySnapshot(
            id: "architecture-review",
            workspaceRoot: "/tmp/workspace",
            buildTool: .swiftPackage,
            files: [
                RepositoryFile(path: "Sources/OracleOS/Planning/MainPlanner.swift", isDirectory: false),
                RepositoryFile(path: "Sources/OracleOS/Execution/VerifiedExecutor.swift", isDirectory: false),
            ],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(edges: [
                DependencyEdge(
                    sourcePath: "Sources/OracleOS/Planning/MainPlanner.swift",
                    dependency: "Sources/OracleOS/Execution/VerifiedExecutor.swift"
                ),
                DependencyEdge(
                    sourcePath: "Sources/OracleOS/Execution/VerifiedExecutor.swift",
                    dependency: "Sources/OracleOS/Planning/MainPlanner.swift"
                ),
            ]),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: true
        )

        let review = engine.review(
            goalDescription: "refactor planner and execution boundary",
            snapshot: snapshot,
            candidatePaths: [
                "Sources/OracleOS/Planning/MainPlanner.swift",
                "Sources/OracleOS/Execution/VerifiedExecutor.swift",
            ]
        )

        #expect(review.triggered)
        #expect(review.findings.contains(where: { $0.title == "Dependency cycle detected" }))
        #expect(review.governanceReport.violations.contains(where: { $0.ruleID == .evalBeforeGrowth }))
        #expect(review.refactorProposal != nil)
        let affectedModules = review.refactorProposal?.affectedModules ?? []
        #expect(affectedModules.contains("Planning"))
    }

    @Test("Architecture engine flags test-only repair candidates")
    func architectureEngineFlagsTestOnlyRepairCandidates() throws {
        let workspace = try makeArchitectureRankingWorkspace()
        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace.root)
        let engine = ArchitectureEngine()

        let review = engine.reviewCandidatePatch(
            goalDescription: "fix failing calculator behavior",
            snapshot: snapshot,
            candidate: workspace.candidates[1],
            diffSummary: " Tests/ExampleTests/CalculatorTests.swift | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)"
        )

        #expect(review.triggered)
        #expect(review.findings.contains(where: { $0.title == "Test-only repair path" }))
        #expect(review.riskScore >= 0.65)
    }

    @Test("Experiment manager isolates candidate worktrees and keeps main workspace unchanged")
    func experimentManagerIsolatesCandidates() async throws {
        let workspace = try makeCodePlannerWorkspace()
        let workspaceRoot = workspace.root
        let filePath = workspaceRoot.appendingPathComponent("Sources/Example/Calculator.swift", isDirectory: false)
        let baseline = try String(contentsOf: filePath, encoding: .utf8)

        let spec = ExperimentSpec(
            id: "parser-fix",
            goalDescription: "fix parser edge case",
            workspaceRoot: workspaceRoot.path,
            candidates: workspace.candidates
        )

        let manager = ExperimentManager()
        let results = try await manager.run(spec: spec, architectureRiskScore: 0.2)

        #expect(results.count == workspace.candidates.count)
        let selectedResults = results.filter { $0.selected }
        #expect(selectedResults.count == 1)
        #expect(results.contains(where: { $0.succeeded }))

        let selected = try #require(selectedResults.first)
        let replay = manager.replaySelected(from: results)

        #expect(replay?.id == selected.candidate.id)
        #expect(selected.succeeded)
        #expect(FileManager.default.fileExists(atPath: selected.sandboxPath))
        #expect(FileManager.default.fileExists(atPath: manager.resultsURL(for: spec).path))
        #expect(try manager.loadResults(for: spec).count == results.count)
        #expect((try String(contentsOf: filePath, encoding: .utf8)) == baseline)
        #expect(results.allSatisfy { $0.promptDiagnostics?.templateKind == .experimentGeneration })
    }

    @Test("Experiment manager prefers structurally safer passing patch")
    func experimentManagerPrefersStructurallySaferPatch() async throws {
        let workspace = try makeArchitectureRankingWorkspace()
        let spec = ExperimentSpec(
            id: "architecture-ranking",
            goalDescription: "fix failing calculator behavior",
            workspaceRoot: workspace.root.path,
            candidates: workspace.candidates
        )

        let manager = ExperimentManager()
        let results = try await manager.run(spec: spec)

        #expect(results.first?.candidate.id == "source-fix")
        #expect(results.first?.selected == true)
        #expect(results.first?.succeeded == true)
        #expect(results.last?.candidate.id == "test-fix")
        #expect(results.last?.architectureFindings.contains(where: { $0.title == "Test-only repair path" }) == true)
    }

    @Test("CodePlanner keeps direct repair when confidence is high")
    func codePlannerKeepsDirectRepairWhenConfidenceIsHigh() throws {
        let workspace = try makeCodePlannerWorkspace()
        let planner = CodePlanner()
        let graphStore = GraphStore(databaseURL: makeTempGraphURL())
        let memoryStore = UnifiedMemoryStore()
        let goalDescription = "fix failing build in Sources/Example/Calculator.swift"
        for _ in 0..<3 {
            memoryStore.recordFixPattern(
                FixPattern(
                    errorSignature: goalDescription,
                    workspaceRelativePath: "Sources/Example/Calculator.swift",
                    commandCategory: CodeCommandCategory.editFile.rawValue
                ),
                success: true
            )
        }
        let observation = Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: [])
        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace.root)
        let taskContext = TaskContext.from(
            goal: Goal(
                description: goalDescription,
                workspaceRoot: workspace.root.path,
                preferredAgentKind: .code,
                experimentCandidates: workspace.candidates
            ),
            workspaceRoot: workspace.root
        )
        let worldState = WorldState(
            observation: observation,
            repositorySnapshot: snapshot
        )

        let decision = planner.nextStep(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore
        )

        #expect(decision?.executionMode == .direct)
        #expect(decision?.skillName == "edit_file")
        #expect(decision?.experimentSpec == nil)
        #expect(decision?.promptDiagnostics?.templateKind == .codeRepair)
    }

    @Test("CodePlanner escalates uncertain repair into experiments")
    func codePlannerEscalatesUncertainRepairIntoExperiments() throws {
        let workspace = try makeCodePlannerWorkspace()
        let planner = CodePlanner()
        let graphStore = GraphStore(databaseURL: makeTempGraphURL())
        let memoryStore = UnifiedMemoryStore()
        let observation = Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: [])
        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace.root)
        let taskContext = TaskContext.from(
            goal: Goal(
                description: "fix failing build in Sources/Example/Calculator.swift\nTests/ExampleTests/CalculatorTests.swift",
                workspaceRoot: workspace.root.path,
                preferredAgentKind: .code,
                experimentCandidates: workspace.candidates
            ),
            workspaceRoot: workspace.root
        )
        let worldState = WorldState(
            observation: observation,
            repositorySnapshot: snapshot
        )

        let decision = planner.nextStep(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore
        )

        #expect(decision?.executionMode == .experiment)
        #expect(decision?.skillName == "generate_patch")
        #expect(decision?.experimentSpec?.candidates.count == 2)
        #expect(decision?.experimentDecision?.reason == "ambiguous edit target")
        #expect(decision?.promptDiagnostics?.templateKind == .codeRepair)
    }

    @Test("Rejected approaches bias CodePlanner toward experiments")
    func rejectedApproachesBiasPlannerTowardExperiments() throws {
        let workspace = try makeCodePlannerWorkspace()
        let store = try ProjectMemoryStore(projectRootURL: workspace.root)
        _ = try store.writeRejectedApproachDraft(
            title: "Do not single-path edit calculator directly",
            summary: "Editing Sources/Example/Calculator.swift directly was previously rejected.",
            knowledgeClass: .reusable,
            affectedModules: ["Sources/Example"],
            body: "Avoid direct single-path repair on Sources/Example/Calculator.swift."
        )

        let planner = CodePlanner()
        let graphStore = GraphStore(databaseURL: makeTempGraphURL())
        let memoryStore = UnifiedMemoryStore()
        memoryStore.setWorkspaceRoot(workspace.root.path)
        let taskContext = TaskContext.from(
            goal: Goal(
                description: "fix failing build in Sources/Example/Calculator.swift",
                workspaceRoot: workspace.root.path,
                preferredAgentKind: .code,
                experimentCandidates: workspace.candidates
            ),
            workspaceRoot: workspace.root
        )
        let worldState = WorldState(
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: RepositoryIndexer().index(workspaceRoot: workspace.root)
        )

        let decision = planner.nextStep(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore
        )

        #expect(decision?.executionMode == .experiment)
        #expect(decision?.experimentDecision?.reason == "previous approaches were rejected")
    }

    @Test("Known-good patterns can narrow an ambiguous repair back to direct execution")
    func knownGoodPatternsNarrowAmbiguousRepair() throws {
        let workspace = try makeCodePlannerWorkspace()
        let store = try ProjectMemoryStore(projectRootURL: workspace.root)
        _ = try store.writeKnownGoodPatternDraft(
            title: "Calculator source repair is reliable",
            summary: "Fixes usually land in Sources/Example/Calculator.swift.",
            knowledgeClass: .reusable,
            affectedModules: ["Sources/Example"],
            body: "Prefer Sources/Example/Calculator.swift when this task mentions both source and tests."
        )

        let planner = CodePlanner()
        let graphStore = GraphStore(databaseURL: makeTempGraphURL())
        let memoryStore = UnifiedMemoryStore()
        memoryStore.setWorkspaceRoot(workspace.root.path)
        let taskContext = TaskContext.from(
            goal: Goal(
                description: "fix failing build in Sources/Example/Calculator.swift\nTests/ExampleTests/CalculatorTests.swift",
                workspaceRoot: workspace.root.path,
                preferredAgentKind: .code,
                experimentCandidates: workspace.candidates
            ),
            workspaceRoot: workspace.root
        )
        let worldState = WorldState(
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: RepositoryIndexer().index(workspaceRoot: workspace.root)
        )

        let decision = planner.nextStep(
            taskContext: taskContext,
            worldState: worldState,
            graphStore: graphStore,
            memoryStore: memoryStore
        )

        #expect(decision?.executionMode == .direct)
        #expect(decision?.skillName == "edit_file")
        #expect(decision?.actionContract.workspaceRelativePath == "Sources/Example/Calculator.swift")
        #expect(decision?.promptDiagnostics?.templateKind == .codeRepair)
    }

    @Test("CodePlanner attaches workflow prompt diagnostics when workflow reuse wins")
    func codePlannerAttachesWorkflowPromptDiagnostics() throws {
        let workspace = try makeCodePlannerWorkspace()
        let workflowIndex = WorkflowIndex()
        workflowIndex.add(
            WorkflowPlan(
                id: "source-workflow",
                agentKind: .code,
                goalPattern: "fix calculator behavior",
                steps: [
                    WorkflowStep(
                        agentKind: .code,
                        stepPhase: .engineering,
                        actionContract: ActionContract(
                            id: "edit-source",
                            agentKind: .code,
                            skillName: "edit_file",
                            targetRole: nil,
                            targetLabel: "Calculator.swift",
                            locatorStrategy: "path",
                            workspaceRelativePath: "Sources/Example/Calculator.swift",
                            commandCategory: CodeCommandCategory.editFile.rawValue
                        ),
                        fromPlanningStateID: "workspace|dirty"
                    ),
                ],
                successRate: 0.9,
                repeatedTraceSegmentCount: 3,
                replayValidationSuccess: 1,
                promotionStatus: .promoted
            )
        )

        let planner = CodePlanner(workflowIndex: workflowIndex)
        let decision = planner.nextStep(
            taskContext: TaskContext.from(
                goal: Goal(
                    description: "fix calculator behavior",
                    workspaceRoot: workspace.root.path,
                    preferredAgentKind: .code
                ),
                workspaceRoot: workspace.root
            ),
            worldState: WorldState(
                observationHash: "workspace-hash",
                planningState: PlanningState(
                    id: PlanningStateID(rawValue: "workspace|dirty"),
                    clusterKey: StateClusterKey(rawValue: "workspace|dirty"),
                    appID: "Workspace",
                    domain: nil,
                    windowClass: nil,
                    taskPhase: "engineering",
                    focusedRole: nil,
                    modalClass: nil,
                    navigationClass: "code",
                    controlContext: nil
                ),
                observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
                repositorySnapshot: RepositoryIndexer().index(workspaceRoot: workspace.root)
            ),
            graphStore: GraphStore(databaseURL: makeTempGraphURL()),
            memoryStore: UnifiedMemoryStore()
        )

        #expect(decision?.source == .workflow)
        #expect(decision?.workflowID == "source-workflow")
        #expect(decision?.promptDiagnostics?.templateKind == .workflowSelection)
    }

    @Test("Workflow retriever uses project memory to prefer the safer workflow")
    func workflowRetrieverUsesProjectMemoryBias() throws {
        let workspace = try makeCodePlannerWorkspace()
        let store = try ProjectMemoryStore(projectRootURL: workspace.root)
        _ = try store.writeKnownGoodPatternDraft(
            title: "Calculator source repair flow",
            summary: "Prefer workflows that operate on Sources/Example/Calculator.swift.",
            knowledgeClass: .reusable,
            affectedModules: ["Sources/Example"],
            body: "Source repair workflows are preferred for calculator failures."
        )
        _ = try store.writeRejectedApproachDraft(
            title: "Avoid test-first workflow",
            summary: "Do not prioritize Tests/ExampleTests/CalculatorTests.swift in repair workflows.",
            knowledgeClass: .reusable,
            affectedModules: ["Tests/ExampleTests"],
            body: "Test-first calculator repair workflows are rejected."
        )

        let workflowIndex = WorkflowIndex()
        workflowIndex.add(
            WorkflowPlan(
                id: "source-workflow",
                agentKind: .code,
                goalPattern: "repair calculator behavior",
                steps: [
                    WorkflowStep(
                        agentKind: .code,
                        stepPhase: .engineering,
                        actionContract: ActionContract(
                            id: "edit-source",
                            agentKind: .code,
                            skillName: "edit_file",
                            targetRole: nil,
                            targetLabel: "Calculator.swift",
                            locatorStrategy: "path",
                            workspaceRelativePath: "Sources/Example/Calculator.swift"
                        ),
                        fromPlanningStateID: "workspace|dirty"
                    ),
                ],
                successRate: 0.9,
                repeatedTraceSegmentCount: 3,
                replayValidationSuccess: 1,
                promotionStatus: .promoted
            )
        )
        workflowIndex.add(
            WorkflowPlan(
                id: "test-workflow",
                agentKind: .code,
                goalPattern: "repair calculator behavior",
                steps: [
                    WorkflowStep(
                        agentKind: .code,
                        stepPhase: .engineering,
                        actionContract: ActionContract(
                            id: "edit-test",
                            agentKind: .code,
                            skillName: "edit_file",
                            targetRole: nil,
                            targetLabel: "CalculatorTests.swift",
                            locatorStrategy: "path",
                            workspaceRelativePath: "Tests/ExampleTests/CalculatorTests.swift"
                        ),
                        fromPlanningStateID: "workspace|dirty"
                    ),
                ],
                successRate: 0.95,
                repeatedTraceSegmentCount: 3,
                replayValidationSuccess: 1,
                promotionStatus: .promoted
            )
        )

        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace.root)
        let taskContext = TaskContext.from(
            goal: Goal(
                description: "fix calculator behavior",
                workspaceRoot: workspace.root.path,
                preferredAgentKind: .code
            ),
            workspaceRoot: workspace.root
        )
        let worldState = WorldState(
            observationHash: "workspace-hash",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "workspace|dirty"),
                clusterKey: StateClusterKey(rawValue: "workspace|dirty"),
                appID: "Workspace",
                domain: nil,
                windowClass: nil,
                taskPhase: "engineering",
                focusedRole: nil,
                modalClass: nil,
                navigationClass: "code",
                controlContext: nil
            ),
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: snapshot
        )

        let memoryStore = UnifiedMemoryStore()
        memoryStore.setWorkspaceRoot(workspace.root.path)

        let match = WorkflowRetriever().retrieve(
            goal: taskContext.goal,
            taskContext: taskContext,
            worldState: worldState,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore
        )

        #expect(match?.plan.id == "source-workflow")
        #expect(match?.projectMemoryRefs.contains(where: { $0.kind == .knownGoodPattern }) == true)
        #expect(match?.projectMemoryRefs.contains(where: { $0.kind == .rejectedApproach }) == true)
    }

    @Test("Workflow retriever uses execution and pattern memory to prefer the known fix path")
    func workflowRetrieverUsesExecutionPatternMemoryBias() throws {
        let workspace = try makeCodePlannerWorkspace()
        let workflowIndex = WorkflowIndex()
        workflowIndex.add(
            WorkflowPlan(
                id: "source-workflow",
                agentKind: .code,
                goalPattern: "repair calculator behavior",
                steps: [
                    WorkflowStep(
                        agentKind: .code,
                        stepPhase: .engineering,
                        actionContract: ActionContract(
                            id: "edit-source",
                            agentKind: .code,
                            skillName: "edit_file",
                            targetRole: nil,
                            targetLabel: "Calculator.swift",
                            locatorStrategy: "path",
                            workspaceRelativePath: "Sources/Example/Calculator.swift",
                            commandCategory: CodeCommandCategory.editFile.rawValue
                        ),
                        fromPlanningStateID: "workspace|dirty"
                    ),
                ],
                successRate: 0.9,
                repeatedTraceSegmentCount: 3,
                replayValidationSuccess: 1,
                promotionStatus: .promoted
            )
        )
        workflowIndex.add(
            WorkflowPlan(
                id: "test-workflow",
                agentKind: .code,
                goalPattern: "repair calculator behavior",
                steps: [
                    WorkflowStep(
                        agentKind: .code,
                        stepPhase: .engineering,
                        actionContract: ActionContract(
                            id: "edit-test",
                            agentKind: .code,
                            skillName: "edit_file",
                            targetRole: nil,
                            targetLabel: "CalculatorTests.swift",
                            locatorStrategy: "path",
                            workspaceRelativePath: "Tests/ExampleTests/CalculatorTests.swift",
                            commandCategory: CodeCommandCategory.editFile.rawValue
                        ),
                        fromPlanningStateID: "workspace|dirty"
                    ),
                ],
                successRate: 0.95,
                repeatedTraceSegmentCount: 3,
                replayValidationSuccess: 1,
                promotionStatus: .promoted
            )
        )

        let snapshot = RepositoryIndexer().index(workspaceRoot: workspace.root)
        let taskContext = TaskContext.from(
            goal: Goal(
                description: "fix calculator behavior",
                workspaceRoot: workspace.root.path,
                preferredAgentKind: .code
            ),
            workspaceRoot: workspace.root
        )
        let worldState = WorldState(
            observationHash: "workspace-hash",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "workspace|dirty"),
                clusterKey: StateClusterKey(rawValue: "workspace|dirty"),
                appID: "Workspace",
                domain: nil,
                windowClass: nil,
                taskPhase: "engineering",
                focusedRole: nil,
                modalClass: nil,
                navigationClass: "code",
                controlContext: nil
            ),
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: snapshot
        )
        let memoryStore = UnifiedMemoryStore()
        for _ in 0..<3 {
            memoryStore.recordFixPattern(
                FixPattern(
                    errorSignature: taskContext.goal.description,
                    workspaceRelativePath: "Sources/Example/Calculator.swift",
                    commandCategory: CodeCommandCategory.editFile.rawValue
                ),
                success: true
            )
        }

        let match = WorkflowRetriever().retrieve(
            goal: taskContext.goal,
            taskContext: taskContext,
            worldState: worldState,
            workflowIndex: workflowIndex,
            memoryStore: memoryStore
        )

        #expect(match?.plan.id == "source-workflow")
    }

    @Test("Experiment results rank smaller passing patches ahead of larger ones")
    func experimentResultsRankCorrectly() {
        let comparator = ResultComparator()
        let workspaceRoot = "/tmp/workspace"
        let minimal = ExperimentResult(
            experimentID: "exp-1",
            candidate: CandidatePatch(
                id: "minimal",
                title: "Minimal",
                summary: "Small fix",
                workspaceRelativePath: "Sources/Parser.swift",
                content: "let a = 1\n"
            ),
            sandboxPath: "/tmp/minimal",
            commandResults: [
                CommandResult(
                    succeeded: true,
                    exitCode: 0,
                    stdout: "",
                    stderr: "",
                    elapsedMs: 25,
                    workspaceRoot: workspaceRoot,
                    category: .test,
                    summary: "swift test"
                ),
            ],
            diffSummary: " Sources/Parser.swift | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)",
            architectureRiskScore: 0.2
        )
        let rewrite = ExperimentResult(
            experimentID: "exp-1",
            candidate: CandidatePatch(
                id: "rewrite",
                title: "Rewrite",
                summary: "Large fix",
                workspaceRelativePath: "Sources/Parser.swift",
                content: "let a = 2\nlet b = 3\nlet c = 4\n"
            ),
            sandboxPath: "/tmp/rewrite",
            commandResults: [
                CommandResult(
                    succeeded: true,
                    exitCode: 0,
                    stdout: "",
                    stderr: "",
                    elapsedMs: 30,
                    workspaceRoot: workspaceRoot,
                    category: .test,
                    summary: "swift test"
                ),
            ],
            diffSummary: " Sources/Parser.swift | 8 +++++---\n 1 file changed, 5 insertions(+), 3 deletions(-)",
            architectureRiskScore: 0.2
        )

        let ranked = comparator.sort([rewrite, minimal])

        #expect(ranked.first?.candidate.id == "minimal")
    }

    @Test("Experiment knowledge tier does not promote directly to stable graph")
    func experimentTierDoesNotPromoteDirectly() {
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let fromState = planningState(id: "code|build-failing", taskPhase: "build-failing")
        let toState = planningState(id: "code|build-passing", taskPhase: "build-passing")
        let contract = ActionContract(
            id: "code|edit_file|Package.swift|Sources/Parser.swift",
            agentKind: .code,
            skillName: "edit_file",
            targetRole: nil,
            targetLabel: nil,
            locatorStrategy: "code-planner",
            workspaceRelativePath: "Sources/Parser.swift",
            commandCategory: CodeCommandCategory.editFile.rawValue,
            plannerFamily: PlannerFamily.code.rawValue
        )

        for _ in 0..<5 {
            store.recordTransition(
                VerifiedTransition(
                    fromPlanningStateID: fromState.id,
                    toPlanningStateID: toState.id,
                    actionContractID: contract.id,
                    agentKind: .code,
                    workspaceRelativePath: "Sources/Parser.swift",
                    commandCategory: CodeCommandCategory.editFile.rawValue,
                    plannerFamily: PlannerFamily.code.rawValue,
                    postconditionClass: .textChanged,
                    verified: true,
                    failureClass: nil,
                    latencyMs: 100,
                    knowledgeTier: .experiment
                ),
                actionContract: contract,
                fromState: fromState,
                toState: toState
            )
        }

        let promoted = store.promoteEligibleEdges()

        #expect(promoted.isEmpty)
        #expect(store.allStableEdges().isEmpty)
        #expect(store.allCandidateEdges().first?.knowledgeTier == .experiment)
    }

    private func planningState(id: String, taskPhase: String) -> PlanningState {
        PlanningState(
            id: PlanningStateID(rawValue: id),
            clusterKey: StateClusterKey(rawValue: id),
            appID: "Workspace",
            domain: nil,
            windowClass: nil,
            taskPhase: taskPhase,
            focusedRole: nil,
            modalClass: nil,
            navigationClass: "code",
            controlContext: nil
        )
    }

    private func makeTempGraphURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("graph.sqlite3", isDirectory: false)
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeCommittedGitWorkspace() throws -> URL {
        let root = makeTempDirectory()
        let sourceDir = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = sourceDir.appendingPathComponent("Parser.swift", isDirectory: false)
        try "struct Parser {\n    let mode = 1\n}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "codex@example.com"], in: root)
        try runGit(["config", "user.name", "Codex"], in: root)
        try runGit(["add", "."], in: root)
        try runGit(["commit", "-m", "Initial commit"], in: root)

        return root
    }

    private func makeCodePlannerWorkspace() throws -> BrokenCodePlannerWorkspace {
        let root = makeTempDirectory()
        let sources = root.appendingPathComponent("Sources/Example", isDirectory: true)
        let tests = root.appendingPathComponent("Tests/ExampleTests", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)

        let package = """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "Example",
            products: [
                .library(name: "Example", targets: ["Example"]),
            ],
            targets: [
                .target(name: "Example"),
                .testTarget(name: "ExampleTests", dependencies: ["Example"]),
            ]
        )
        """

        let brokenSource = """
        public struct Calculator {
            public static func double(_ value: Int) -> Int {
                value *
            }
        }
        """

        let goodSource = """
        public struct Calculator {
            public static func double(_ value: Int) -> Int {
                value * 2
            }
        }
        """

        let failingTestSource = """
        public struct Calculator {
            public static func double(_ value: Int) -> Int {
                value * 3
            }
        }
        """

        let testSource = """
        import Testing
        @testable import Example

        @Test func doublesInput() {
            #expect(Calculator.double(2) == 4)
        }
        """

        try package.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try brokenSource.write(to: sources.appendingPathComponent("Calculator.swift"), atomically: true, encoding: .utf8)
        try testSource.write(to: tests.appendingPathComponent("CalculatorTests.swift"), atomically: true, encoding: .utf8)

        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "codex@example.com"], in: root)
        try runGit(["config", "user.name", "Codex"], in: root)
        try runGit(["add", "."], in: root)
        try runGit(["commit", "-m", "Initial commit"], in: root)

        return BrokenCodePlannerWorkspace(
            root: root,
            candidates: [
                CandidatePatch(
                    id: "restore",
                    title: "Restore valid calculator implementation",
                    summary: "Restore the known-good implementation so build and tests pass.",
                    workspaceRelativePath: "Sources/Example/Calculator.swift",
                    content: goodSource,
                    hypothesis: "Revert the broken edit."
                ),
                CandidatePatch(
                    id: "compile-first",
                    title: "Replace build failure with test failure",
                    summary: "Compile first, then inspect the remaining test failure.",
                    workspaceRelativePath: "Sources/Example/Calculator.swift",
                    content: failingTestSource,
                    hypothesis: "Compile first, then inspect the failing assertion."
                ),
            ]
        )
    }

    private func makeArchitectureRankingWorkspace() throws -> BrokenCodePlannerWorkspace {
        let root = makeTempDirectory()
        let sources = root.appendingPathComponent("Sources/Example", isDirectory: true)
        let tests = root.appendingPathComponent("Tests/ExampleTests", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)

        let package = """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "Example",
            products: [
                .library(name: "Example", targets: ["Example"]),
            ],
            targets: [
                .target(name: "Example"),
                .testTarget(name: "ExampleTests", dependencies: ["Example"]),
            ]
        )
        """

        let wrongSource = """
        public struct Calculator {
            public static func double(_ value: Int) -> Int {
                value * 3
            }
        }
        """

        let goodSource = """
        public struct Calculator {
            public static func double(_ value: Int) -> Int {
                value * 2
            }
        }
        """

        let permissiveTest = """
        import Testing
        @testable import Example

        @Test func doublesInput() {
            #expect(Calculator.double(2) == 6)
        }
        """

        let strictTest = """
        import Testing
        @testable import Example

        @Test func doublesInput() {
            #expect(Calculator.double(2) == 4)
        }
        """

        try package.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try wrongSource.write(to: sources.appendingPathComponent("Calculator.swift"), atomically: true, encoding: .utf8)
        try strictTest.write(to: tests.appendingPathComponent("CalculatorTests.swift"), atomically: true, encoding: .utf8)

        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "codex@example.com"], in: root)
        try runGit(["config", "user.name", "Codex"], in: root)
        try runGit(["add", "."], in: root)
        try runGit(["commit", "-m", "Initial commit"], in: root)

        return BrokenCodePlannerWorkspace(
            root: root,
            candidates: [
                CandidatePatch(
                    id: "source-fix",
                    title: "Fix source implementation",
                    summary: "Restore the correct calculator logic in source.",
                    workspaceRelativePath: "Sources/Example/Calculator.swift",
                    content: goodSource,
                    hypothesis: "The bug belongs in production code."
                ),
                CandidatePatch(
                    id: "test-fix",
                    title: "Relax the test expectation",
                    summary: "Make the test accept the current wrong behavior.",
                    workspaceRelativePath: "Tests/ExampleTests/CalculatorTests.swift",
                    content: permissiveTest,
                    hypothesis: "Silence the failing test instead of fixing production behavior."
                ),
            ]
        )
    }

    private func runGit(_ arguments: [String], in root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = root
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw NSError(
                domain: "DigitalEngineerLayerTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }
    }
}

private struct BrokenCodePlannerWorkspace {
    let root: URL
    let candidates: [CandidatePatch]
}
