import Foundation
import Testing
@testable import OracleOS

@Suite("Governance Enforcement")
struct GovernanceEnforcementTests {

    @Test("Episode residue is kept out of canonical project memory")
    func episodeResidueIsNotIndexed() throws {
        let projectRoot = makeTempDirectory()
        let store = try ProjectMemoryStore(projectRootURL: projectRoot)

        let ref = try store.writeDraft(
            ProjectMemoryDraft(
                kind: .openProblem,
                knowledgeClass: .episode,
                title: "One-off flaky timeout",
                summary: "Transient CI timeout during one run.",
                affectedModules: ["Tests/OracleOSEvals"],
                evidenceRefs: ["trace:timeout-1"],
                sourceTraceIDs: ["trace-timeout-1"],
                body: "This was a one-off timeout and should stay trace-local."
            )
        )

        let indexed = store.query(text: "flaky timeout")

        #expect(indexed.isEmpty)
        #expect(ref.knowledgeClass == .episode)
        #expect(ref.path.contains("/.oracle/project-memory-episode/"))
        #expect(FileManager.default.fileExists(atPath: ref.path))
    }

    @Test("Direct stable transition recording is sanitized to candidate knowledge")
    func directStableRecordingIsSanitized() {
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let fromState = planningState(id: "os|finder|browse", taskPhase: "browse")
        let toState = planningState(id: "os|finder|rename", taskPhase: "rename")
        let contract = ActionContract(
            id: "click|AXButton|Rename|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Rename",
            locatorStrategy: "query"
        )

        store.recordTransition(
            VerifiedTransition(
                fromPlanningStateID: fromState.id,
                toPlanningStateID: toState.id,
                actionContractID: contract.id,
                postconditionClass: .focusChanged,
                verified: true,
                failureClass: nil,
                latencyMs: 50,
                knowledgeTier: .stable
            ),
            actionContract: contract,
            fromState: fromState,
            toState: toState
        )

        #expect(store.allStableEdges().isEmpty)
        #expect(store.allCandidateEdges().first?.knowledgeTier == .candidate)
    }

    @Test("Recovery-tagged transitions cannot be recorded as stable knowledge")
    func recoveryKnowledgeIsForcedToRecoveryTier() {
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let state = planningState(id: "os|chrome|modal", taskPhase: "modal")
        let contract = ActionContract(
            id: "click|AXButton|Dismiss|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Dismiss",
            locatorStrategy: "query"
        )

        store.recordTransition(
            VerifiedTransition(
                fromPlanningStateID: state.id,
                toPlanningStateID: state.id,
                actionContractID: contract.id,
                postconditionClass: .elementDisappeared,
                verified: true,
                failureClass: nil,
                latencyMs: 30,
                recoveryTagged: true,
                knowledgeTier: .stable
            ),
            actionContract: contract,
            fromState: state,
            toState: state
        )

        #expect(store.allStableEdges().isEmpty)
        #expect(store.allCandidateEdges().first?.knowledgeTier == .recovery)
    }

    @Test("Workflow promotion rejects obvious episode residue")
    func workflowPromotionRejectsEpisodeResidue() {
        let policy = WorkflowPromotionPolicy()
        let plan = WorkflowPlan(
            agentKind: .code,
            goalPattern: "fix parser",
            steps: [
                WorkflowStep(
                    agentKind: .code,
                    stepPhase: .engineering,
                    actionContract: ActionContract(
                        id: "edit|parser",
                        agentKind: .code,
                        skillName: "edit_file",
                        targetRole: nil,
                        targetLabel: "Parser.swift",
                        locatorStrategy: "path",
                        workspaceRelativePath: "/tmp/oracle-run-123/.oracle/experiments/exp-1/candidate-a/Sources/Parser.swift"
                    )
                ),
            ],
            successRate: 0.95,
            sourceTraceRefs: ["s1:1", "s2:1", "s3:1"],
            evidenceTiers: [.candidate],
            repeatedTraceSegmentCount: 3,
            replayValidationSuccess: 1,
            promotionStatus: .candidate
        )

        #expect(policy.shouldPromote(plan) == false)
    }

    @Test("Workflow promotion rejects single-episode repeated evidence")
    func workflowPromotionRejectsSingleEpisodeEvidence() {
        let events = [
            workflowEvent(sessionID: "session-1", taskID: "task-1", stepID: 1, actionName: "navigate_url", actionTarget: "https://example.com/report/1", actionContractID: "open|url", postconditionClass: "urlChanged", planningStateID: "browser|report"),
            workflowEvent(sessionID: "session-1", taskID: "task-1", stepID: 2, actionName: "click", actionTarget: "Download", actionContractID: "click|download", postconditionClass: "elementAppeared", planningStateID: "browser|download"),
            workflowEvent(sessionID: "session-1", taskID: "task-1", stepID: 3, actionName: "navigate_url", actionTarget: "https://example.com/report/2", actionContractID: "open|url", postconditionClass: "urlChanged", planningStateID: "browser|report"),
            workflowEvent(sessionID: "session-1", taskID: "task-1", stepID: 4, actionName: "click", actionTarget: "Download", actionContractID: "click|download", postconditionClass: "elementAppeared", planningStateID: "browser|download"),
        ]

        let synthesized = WorkflowSynthesizer().synthesize(
            goalPattern: "download report",
            events: events
        )

        #expect(synthesized.isEmpty)
    }

    @Test("Architecture-expanding changes without eval coverage produce a hard governance failure")
    func architectureGrowthRequiresCoverage() {
        let engine = ArchitectureEngine()
        let snapshot = RepositorySnapshot(
            id: "governance-review",
            workspaceRoot: "/tmp/workspace",
            buildTool: .swiftPackage,
            files: [
                RepositoryFile(path: "Sources/OracleOS/Runtime/RuntimeOrchestrator.swift", isDirectory: false),
            ],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: true
        )

        let review = engine.review(
            goalDescription: "refactor runtime graph boundary",
            snapshot: snapshot,
            candidatePaths: [
                "Sources/OracleOS/Runtime/RuntimeOrchestrator.swift",
                "Sources/OracleOS/WorldModel/Graph/GraphStore.swift",
            ]
        )

        #expect(review.governanceReport.isBlocking)
        #expect(review.governanceReport.hardFailures.contains(where: { $0.ruleID == .evalBeforeGrowth }))
    }

    @Test("Loop changes cannot absorb experiment or ranking internals")
    func loopOwnershipDriftIsBlocking() {
        let engine = ArchitectureEngine()
        let snapshot = RepositorySnapshot(
            id: "loop-review",
            workspaceRoot: "/tmp/workspace",
            buildTool: .swiftPackage,
            files: [
                RepositoryFile(path: "Sources/OracleOS/Execution/Loop/AgentLoop.swift", isDirectory: false),
                RepositoryFile(path: "Sources/OracleOS/Execution/Experiments/ExperimentManager.swift", isDirectory: false),
                RepositoryFile(path: "Sources/OracleOS/Search/Ranking/ElementRanker.swift", isDirectory: false),
                RepositoryFile(path: "Tests/OracleOSTests/Core/GraphAwareLoopTests.swift", isDirectory: false),
            ],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: true
        )

        let review = engine.review(
            goalDescription: "tighten loop orchestration around experiments",
            snapshot: snapshot,
            candidatePaths: [
                "Sources/OracleOS/Execution/Loop/AgentLoop.swift",
                "Sources/OracleOS/Execution/Experiments/ExperimentManager.swift",
            ]
        )

        #expect(review.governanceReport.isBlocking)
        #expect(review.governanceReport.hardFailures.contains(where: { $0.title == "Loop orchestration drift" }))
    }

    @Test("Planner changes cannot absorb local ranking or execution layers")
    func plannerBoundaryDriftIsBlocking() {
        let engine = ArchitectureEngine()
        let snapshot = RepositorySnapshot(
            id: "planner-review",
            workspaceRoot: "/tmp/workspace",
            buildTool: .swiftPackage,
            files: [
                RepositoryFile(path: "Sources/OracleOS/Planning/MainPlanner.swift", isDirectory: false),
                RepositoryFile(path: "Sources/OracleOS/Search/Ranking/ElementRanker.swift", isDirectory: false),
                RepositoryFile(path: "Tests/OracleOSTests/Core/GovernanceEnforcementTests.swift", isDirectory: false),
            ],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: true
        )

        let review = engine.review(
            goalDescription: "planner chooses exact ranked target",
            snapshot: snapshot,
            candidatePaths: [
                "Sources/OracleOS/Planning/MainPlanner.swift",
                "Sources/OracleOS/Search/Ranking/ElementRanker.swift",
                "Tests/OracleOSTests/Core/GovernanceEnforcementTests.swift",
            ]
        )

        #expect(review.governanceReport.isBlocking)
        #expect(review.governanceReport.hardFailures.contains(where: { $0.title == "Planner/local-resolution boundary drift" }))
    }

    @Test("AgentLoop no longer invokes the legacy execution driver")
    func agentLoopDoesNotInvokeLegacyExecutionDriver() throws {
        let root = repositoryRoot()
        let loopDir = root.appendingPathComponent("Sources/OracleOS/Execution/Loop", isDirectory: true)
        let enumerator = FileManager.default.enumerator(at: loopDir, includingPropertiesForKeys: nil)

        var offendingFiles: [String] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let contents = try String(contentsOf: fileURL)
            if contents.contains("executionDriver.execute") {
                offendingFiles.append(fileURL.lastPathComponent)
            }
        }

        #expect(offendingFiles.isEmpty, "AgentLoop should not invoke the legacy execution driver, found: \(offendingFiles)")
    }

    @Test("AgentLoop source file stays below 150 lines")
    func agentLoopSourceFileStaysBelowOneFiftyLines() throws {
        let agentLoopURL = repositoryRoot().appendingPathComponent(
            "Sources/OracleOS/Execution/Loop/AgentLoop.swift",
            isDirectory: false
        )
        let lineCount = try String(contentsOf: agentLoopURL).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count

        #expect(lineCount < 150, "AgentLoop.swift should stay below 150 lines, found \(lineCount)")
    }

    @Test("Workspace runner blocks unsupported arbitrary shell execution")
    func workspaceRunnerBlocksArbitraryShellExecution() throws {
        let root = makeTempDirectory()
        let runner = WorkspaceRunner()
        let spec = CommandSpec(
            category: .build,
            executable: "/bin/sh",
            arguments: ["-c", "echo unsafe"],
            workspaceRoot: root.path,
            summary: "arbitrary shell build"
        )

        #expect(throws: WorkspaceRunnerError.unsupportedCommand(spec.summary)) {
            try runner.execute(spec: spec)
        }
    }

    @Test("AgentLoop must not contain plan scoring logic")
    func agentLoopDoesNotScorePlans() throws {
        let contents = try agentLoopContents()
        let forbidden = ["planEvaluator", "PlanEvaluator", "PlanEvaluator(", "scorePlan", "rankPlan", "PlanCandidate"]
        for term in forbidden {
            #expect(!contents.contains(term), "AgentLoop.swift must not contain '\(term)' - plan scoring belongs in PlanEvaluator")
        }
    }

    @Test("AgentLoop must not route memory directly")
    func agentLoopDoesNotRouteMemory() throws {
        let contents = try agentLoopContents()
        let forbidden = ["MemoryRouter(", "PatternMemoryStore(", "ExecutionMemoryStore("]
        for term in forbidden {
            #expect(!contents.contains(term), "AgentLoop.swift must not contain '\(term)' - memory routing belongs in MemoryRouter")
        }
    }

    @Test("AgentLoop must not update graph directly")
    func agentLoopDoesNotUpdateGraph() throws {
        let contents = try agentLoopContents()
        let forbidden = ["graphStore.recordTransition", "graphStore.promote", "graphStore.insert"]
        for term in forbidden {
            #expect(!contents.contains(term), "AgentLoop.swift must not contain '\(term)' - graph updates belong outside the loop boundary")
        }
    }

    @Test("AgentLoop must not analyze architecture")
    func agentLoopDoesNotAnalyzeArchitecture() throws {
        let contents = try agentLoopContents()
        let forbidden = ["ArchitectureEngine(", "architectureEngine.review"]
        for term in forbidden {
            #expect(!contents.contains(term), "AgentLoop.swift must not contain '\(term)' - architecture analysis belongs in CodePlanner")
        }
    }

    @Test("AgentLoop must not compare experiments")
    func agentLoopDoesNotCompareExperiments() throws {
        let contents = try agentLoopContents()
        let forbidden = ["ResultComparator(", "PatchRanker(", "comparator.sort"]
        for term in forbidden {
            #expect(!contents.contains(term), "AgentLoop.swift must not contain '\(term)' - experiment comparison belongs in ExperimentCoordinator")
        }
    }

    private func agentLoopContents() throws -> String {
        let agentLoopURL = repositoryRoot().appendingPathComponent(
            "Sources/OracleOS/Execution/Loop/AgentLoop.swift",
            isDirectory: false
        )
        return try String(contentsOf: agentLoopURL)
    }

    private func planningState(id: String, taskPhase: String) -> PlanningState {
        PlanningState(
            id: PlanningStateID(rawValue: id),
            clusterKey: StateClusterKey(rawValue: id),
            appID: "TestApp",
            domain: nil,
            windowClass: nil,
            taskPhase: taskPhase,
            focusedRole: nil,
            modalClass: nil,
            navigationClass: "governance",
            controlContext: nil
        )
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while true {
            let packageManifestURL = url.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageManifestURL.path) {
                return url
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                // Reached filesystem root without finding Package.swift; return the current directory.
                return url
            }

            url = parent
        }
    }

    private func makeTempGraphURL() -> URL {
        makeTempDirectory().appendingPathComponent("graph.sqlite3", isDirectory: false)
    }

    private func workflowEvent(
        sessionID: String,
        taskID: String,
        stepID: Int,
        actionName: String,
        actionTarget: String,
        actionContractID: String,
        postconditionClass: String,
        planningStateID: String
    ) -> TraceEvent {
        TraceEvent(
            sessionID: sessionID,
            taskID: taskID,
            stepID: stepID,
            toolName: "agent_loop",
            actionName: actionName,
            actionTarget: actionTarget,
            actionText: nil,
            selectedElementID: nil,
            selectedElementLabel: actionTarget,
            candidateScore: 0.95,
            candidateReasons: ["governance"],
            ambiguityScore: 0.05,
            preObservationHash: "pre-\(sessionID)-\(stepID)",
            postObservationHash: "post-\(sessionID)-\(stepID)",
            planningStateID: planningStateID,
            beliefSnapshotID: nil,
            postcondition: postconditionClass,
            postconditionClass: postconditionClass,
            actionContractID: actionContractID,
            executionMode: "direct",
            plannerSource: PlannerSource.workflow.rawValue,
            pathEdgeIDs: ["edge-\(actionContractID)"],
            currentEdgeID: "edge-\(actionContractID)",
            verified: true,
            success: true,
            failureClass: nil,
            recoveryStrategy: nil,
            recoverySource: nil,
            recoveryTagged: false,
            surface: RuntimeSurface.recipe.rawValue,
            policyMode: "confirm-risky",
            protectedOperation: nil,
            approvalRequestID: nil,
            approvalOutcome: nil,
            blockedByPolicy: false,
            appProfile: nil,
            agentKind: AgentKind.os.rawValue,
            domain: "os",
            plannerFamily: PlannerFamily.os.rawValue,
            workspaceRelativePath: nil,
            commandCategory: nil,
            commandSummary: nil,
            repositorySnapshotID: nil,
            buildResultSummary: nil,
            testResultSummary: nil,
            patchID: nil,
            projectMemoryRefs: nil,
            experimentID: nil,
            candidateID: nil,
            sandboxPath: nil,
            selectedCandidate: nil,
            experimentOutcome: nil,
            architectureFindings: nil,
            refactorProposalID: nil,
            knowledgeTier: KnowledgeTier.candidate.rawValue,
            elapsedMs: 15,
            notes: nil
        )
    }
}
