import Foundation
import Testing
@testable import OracleOS

@Suite("Workflow Synthesis")
struct WorkflowSynthesisTests {
    @Test("Repeated verified trace segments become promoted workflow candidates")
    func repeatedSegmentsBecomeWorkflowCandidates() {
        let events = [
            workflowEvent(sessionID: "s1", taskID: "t1", stepID: 1, actionName: "navigate_url", actionTarget: "https://example.com/report/1", actionContractID: "open|url", postconditionClass: "urlChanged", planningStateID: "browser|report"),
            workflowEvent(sessionID: "s1", taskID: "t1", stepID: 2, actionName: "click", actionTarget: "Download", actionContractID: "click|download", postconditionClass: "elementAppeared", planningStateID: "browser|download"),
            workflowEvent(sessionID: "s2", taskID: "t2", stepID: 1, actionName: "navigate_url", actionTarget: "https://example.com/report/2", actionContractID: "open|url", postconditionClass: "urlChanged", planningStateID: "browser|report"),
            workflowEvent(sessionID: "s2", taskID: "t2", stepID: 2, actionName: "click", actionTarget: "Download", actionContractID: "click|download", postconditionClass: "elementAppeared", planningStateID: "browser|download"),
            workflowEvent(sessionID: "s3", taskID: "t3", stepID: 1, actionName: "navigate_url", actionTarget: "https://example.com/report/3", actionContractID: "open|url", postconditionClass: "urlChanged", planningStateID: "browser|report"),
            workflowEvent(sessionID: "s3", taskID: "t3", stepID: 2, actionName: "click", actionTarget: "Download", actionContractID: "click|download", postconditionClass: "elementAppeared", planningStateID: "browser|download"),
        ]

        let plans = WorkflowSynthesizer().synthesize(
            goalPattern: "download report",
            events: events
        )

        #expect(plans.count == 1)
        #expect(plans.first?.repeatedTraceSegmentCount == 3)
        #expect(plans.first?.replayValidationSuccess == 1)
        #expect(plans.first?.promotionStatus == .promoted)
        #expect(plans.first?.parameterSlots.contains(where: { $0.hasPrefix("url_") }) == true)
        #expect(plans.first?.steps.first?.actionContract.targetLabel?.contains("{{url_0}}") == true)
    }

    @Test("Repeated segments must span multiple episodes to become workflow candidates")
    func repeatedSegmentsRequireMultipleEpisodes() {
        let events = [
            workflowEvent(sessionID: "s1", taskID: "t1", stepID: 1, actionName: "navigate_url", actionTarget: "https://example.com/report/1", actionContractID: "open|url", postconditionClass: "urlChanged"),
            workflowEvent(sessionID: "s1", taskID: "t1", stepID: 2, actionName: "click", actionTarget: "Download", actionContractID: "click|download", postconditionClass: "elementAppeared"),
            workflowEvent(sessionID: "s1", taskID: "t1", stepID: 3, actionName: "navigate_url", actionTarget: "https://example.com/report/2", actionContractID: "open|url", postconditionClass: "urlChanged"),
            workflowEvent(sessionID: "s1", taskID: "t1", stepID: 4, actionName: "click", actionTarget: "Download", actionContractID: "click|download", postconditionClass: "elementAppeared"),
        ]

        let plans = WorkflowSynthesizer().synthesize(
            goalPattern: "download report",
            events: events
        )

        #expect(plans.isEmpty)
    }

    @Test("Replay validation gates workflow promotion")
    func replayValidationGatesPromotion() {
        let matching = TraceSegment(
            id: "seg-1",
            taskID: "task-1",
            sessionID: "session-1",
            agentKind: .os,
            events: [
                workflowEvent(sessionID: "session-1", taskID: "task-1", stepID: 1, actionName: "click", actionTarget: "Compose", actionContractID: "click|compose", postconditionClass: "elementAppeared"),
                workflowEvent(sessionID: "session-1", taskID: "task-1", stepID: 2, actionName: "type", actionTarget: "Body", actionContractID: "type|body", postconditionClass: "valueMatched"),
            ]
        )
        let mismatched = TraceSegment(
            id: "seg-2",
            taskID: "task-2",
            sessionID: "session-2",
            agentKind: .os,
            events: [
                workflowEvent(sessionID: "session-2", taskID: "task-2", stepID: 1, actionName: "click", actionTarget: "Compose", actionContractID: "click|compose", postconditionClass: "elementAppeared"),
                workflowEvent(sessionID: "session-2", taskID: "task-2", stepID: 2, actionName: "click", actionTarget: "Discard", actionContractID: "click|discard", postconditionClass: "elementAppeared"),
            ]
        )

        let plan = WorkflowPlan(
            agentKind: .os,
            goalPattern: "open compose",
            steps: [
                WorkflowStep(
                    agentKind: .os,
                    stepPhase: .operatingSystem,
                    actionContract: ActionContract(
                        id: "click|compose",
                        agentKind: .os,
                        skillName: "click",
                        targetRole: nil,
                        targetLabel: "Compose",
                        locatorStrategy: "query"
                    )
                ),
                WorkflowStep(
                    agentKind: .os,
                    stepPhase: .operatingSystem,
                    actionContract: ActionContract(
                        id: "type|body",
                        agentKind: .os,
                        skillName: "type",
                        targetRole: nil,
                        targetLabel: "Body",
                        locatorStrategy: "query"
                    )
                ),
            ],
            successRate: 0.9,
            evidenceTiers: [.candidate],
            repeatedTraceSegmentCount: 3,
            replayValidationSuccess: 0
        )

        let validator = WorkflowReplayValidator()
        let score = validator.validate(plan: plan, against: [matching, mismatched])

        #expect(score == 0.5)
        #expect(
            RecipeValidator.validateWorkflow(
                WorkflowPlan(
                    id: plan.id,
                    agentKind: plan.agentKind,
                    goalPattern: plan.goalPattern,
                    steps: plan.steps,
                    parameterSlots: plan.parameterSlots,
                    successRate: plan.successRate,
                    sourceTraceRefs: plan.sourceTraceRefs,
                    sourceGraphEdgeRefs: plan.sourceGraphEdgeRefs,
                    evidenceTiers: plan.evidenceTiers,
                    repeatedTraceSegmentCount: plan.repeatedTraceSegmentCount,
                    replayValidationSuccess: score,
                    promotionStatus: .candidate
                ),
                against: [matching, mismatched]
            ) == false
        )
    }

    @Test("State-aware replay rejects planning-state drift")
    func replayValidationRejectsPlanningStateDrift() {
        let validSegment = TraceSegment(
            id: "seg-valid",
            taskID: "task-1",
            sessionID: "session-1",
            agentKind: .os,
            events: [
                workflowEvent(sessionID: "session-1", taskID: "task-1", stepID: 1, actionName: "click", actionTarget: "Compose", actionContractID: "click|compose", postconditionClass: "elementAppeared", planningStateID: "gmail|browse"),
                workflowEvent(sessionID: "session-1", taskID: "task-1", stepID: 2, actionName: "type", actionTarget: "Body", actionContractID: "type|body", postconditionClass: "valueMatched", planningStateID: "gmail|compose"),
            ]
        )
        let driftedSegment = TraceSegment(
            id: "seg-drift",
            taskID: "task-2",
            sessionID: "session-2",
            agentKind: .os,
            events: [
                workflowEvent(sessionID: "session-2", taskID: "task-2", stepID: 1, actionName: "click", actionTarget: "Compose", actionContractID: "click|compose", postconditionClass: "elementAppeared", planningStateID: "gmail|browse"),
                workflowEvent(sessionID: "session-2", taskID: "task-2", stepID: 2, actionName: "type", actionTarget: "Body", actionContractID: "type|body", postconditionClass: "valueMatched", planningStateID: "gmail|trash"),
            ]
        )

        let plan = WorkflowPlan(
            agentKind: .os,
            goalPattern: "open compose",
            steps: [
                WorkflowStep(
                    agentKind: .os,
                    stepPhase: .operatingSystem,
                    actionContract: ActionContract(
                        id: "click|compose",
                        agentKind: .os,
                        skillName: "click",
                        targetRole: nil,
                        targetLabel: "Compose",
                        locatorStrategy: "query"
                    ),
                    fromPlanningStateID: "gmail|browse"
                ),
                WorkflowStep(
                    agentKind: .os,
                    stepPhase: .operatingSystem,
                    actionContract: ActionContract(
                        id: "type|body",
                        agentKind: .os,
                        skillName: "type",
                        targetRole: nil,
                        targetLabel: "Body",
                        locatorStrategy: "query"
                    ),
                    fromPlanningStateID: "gmail|compose"
                ),
            ],
            successRate: 0.9,
            evidenceTiers: [.candidate],
            repeatedTraceSegmentCount: 3,
            replayValidationSuccess: 0
        )

        let validator = WorkflowReplayValidator()
        let score = validator.validate(plan: plan, against: [validSegment, driftedSegment])

        #expect(score == 0.5)
    }

    @Test("Stale promoted workflows are not retrieved")
    func staleWorkflowsDecayOutOfRetrieval() {
        let workflowIndex = WorkflowIndex()
        let staleDate = Date(timeIntervalSinceNow: -(40 * 86_400))
        workflowIndex.add(
            WorkflowPlan(
                agentKind: .os,
                goalPattern: "open gmail compose",
                steps: [
                    WorkflowStep(
                        agentKind: .os,
                        stepPhase: .operatingSystem,
                        actionContract: ActionContract(
                            id: "click|compose",
                            agentKind: .os,
                            skillName: "click",
                            targetRole: nil,
                            targetLabel: "Compose",
                            locatorStrategy: "query"
                        ),
                        semanticQuery: ElementQuery(
                            text: "Compose",
                            role: "AXButton",
                            clickable: true,
                            visibleOnly: true,
                            app: "Google Chrome"
                        ),
                        fromPlanningStateID: "gmail|inbox"
                    ),
                ],
                successRate: 0.95,
                sourceTraceRefs: ["s1:1"],
                sourceGraphEdgeRefs: ["edge-1"],
                repeatedTraceSegmentCount: 3,
                replayValidationSuccess: 1,
                promotionStatus: .promoted,
                lastValidatedAt: staleDate,
                lastSucceededAt: staleDate
            )
        )

        let retriever = WorkflowRetriever()
        let match = retriever.retrieve(
            goal: Goal(
                description: "open gmail compose",
                targetApp: "Google Chrome",
                targetDomain: "mail.google.com",
                targetTaskPhase: "compose"
            ),
            taskContext: TaskContext.from(
                goal: Goal(
                    description: "open gmail compose",
                    targetApp: "Google Chrome",
                    targetDomain: "mail.google.com",
                    targetTaskPhase: "compose"
                )
            ),
            worldState: WorldState(
                observationHash: "gmail-hash",
                planningState: PlanningState(
                    id: PlanningStateID(rawValue: "gmail|inbox"),
                    clusterKey: StateClusterKey(rawValue: "gmail|inbox"),
                    appID: "Google Chrome",
                    domain: "mail.google.com",
                    windowClass: nil,
                    taskPhase: "browse",
                    focusedRole: "AXButton",
                    modalClass: nil,
                    navigationClass: "web",
                    controlContext: nil
                ),
                observation: Observation(
                    app: "Google Chrome",
                    windowTitle: "Inbox",
                    url: "https://mail.google.com/mail/u/0/#inbox",
                    focusedElementID: "compose",
                    elements: [
                        UnifiedElement(id: "compose", source: .ax, role: "AXButton", label: "Compose", confidence: 0.98),
                    ]
                ),
                repositorySnapshot: nil
            ),
            workflowIndex: workflowIndex
        )

        #expect(match == nil)
    }

    @Test("Workflow promotion rejects untyped episode residue")
    func workflowPromotionRejectsEpisodeResidue() {
        let policy = WorkflowPromotionPolicy()
        let plan = WorkflowPlan(
            agentKind: .code,
            goalPattern: "repair parser failure",
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
            repeatedTraceSegmentCount: 3,
            replayValidationSuccess: 1,
            promotionStatus: .candidate
        )

        #expect(policy.shouldPromote(plan) == false)
    }

    @Test("Workflow pattern miner rejects sandbox-specific residue")
    func workflowPatternMinerRejectsSandboxResidue() {
        let events = [
            workflowEvent(
                sessionID: "s1",
                taskID: "t1",
                stepID: 1,
                actionName: "edit_file",
                actionTarget: "Parser.swift",
                actionContractID: "edit|parser",
                postconditionClass: "valueMatched",
                planningStateID: "repo|tests-failing",
                agentKind: .code,
                plannerFamily: .code,
                workspaceRelativePath: "/tmp/oracle-run-1/.oracle/experiments/exp-1/candidate-a/Sources/Parser.swift",
                sandboxPath: "/tmp/oracle-run-1/.oracle/experiments/exp-1/candidate-a"
            ),
            workflowEvent(
                sessionID: "s2",
                taskID: "t2",
                stepID: 1,
                actionName: "edit_file",
                actionTarget: "Parser.swift",
                actionContractID: "edit|parser",
                postconditionClass: "valueMatched",
                planningStateID: "repo|tests-failing",
                agentKind: .code,
                plannerFamily: .code,
                workspaceRelativePath: "/tmp/oracle-run-2/.oracle/experiments/exp-2/candidate-b/Sources/Parser.swift",
                sandboxPath: "/tmp/oracle-run-2/.oracle/experiments/exp-2/candidate-b"
            ),
            workflowEvent(
                sessionID: "s3",
                taskID: "t3",
                stepID: 1,
                actionName: "edit_file",
                actionTarget: "Parser.swift",
                actionContractID: "edit|parser",
                postconditionClass: "valueMatched",
                planningStateID: "repo|tests-failing",
                agentKind: .code,
                plannerFamily: .code,
                workspaceRelativePath: "/tmp/oracle-run-3/.oracle/experiments/exp-3/candidate-c/Sources/Parser.swift",
                sandboxPath: "/tmp/oracle-run-3/.oracle/experiments/exp-3/candidate-c"
            ),
        ]

        let patterns = WorkflowPatternMiner().mine(events: events)
        let plans = WorkflowSynthesizer().synthesize(
            goalPattern: "repair parser failure",
            events: events
        )

        #expect(patterns.isEmpty)
        #expect(plans.isEmpty)
    }

    private func workflowEvent(
        sessionID: String,
        taskID: String,
        stepID: Int,
        actionName: String,
        actionTarget: String,
        actionContractID: String,
        postconditionClass: String,
        planningStateID: String? = nil,
        agentKind: AgentKind = .os,
        plannerFamily: PlannerFamily = .os,
        workspaceRelativePath: String? = nil,
        sandboxPath: String? = nil,
        knowledgeTier: KnowledgeTier = .candidate
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
            candidateReasons: ["test"],
            ambiguityScore: 0.05,
            preObservationHash: "pre-\(sessionID)-\(stepID)",
            postObservationHash: "post-\(sessionID)-\(stepID)",
            planningStateID: planningStateID ?? "state-\(taskID)-\(stepID)",
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
            agentKind: agentKind.rawValue,
            domain: agentKind == .code ? "code" : "os",
            plannerFamily: plannerFamily.rawValue,
            workspaceRelativePath: workspaceRelativePath,
            commandCategory: nil,
            commandSummary: nil,
            repositorySnapshotID: nil,
            buildResultSummary: nil,
            testResultSummary: nil,
            patchID: nil,
            projectMemoryRefs: nil,
            experimentID: nil,
            candidateID: nil,
            sandboxPath: sandboxPath,
            selectedCandidate: nil,
            experimentOutcome: nil,
            architectureFindings: nil,
            refactorProposalID: nil,
            knowledgeTier: knowledgeTier.rawValue,
            elapsedMs: 10,
            screenshotPath: nil,
            notes: nil
        )
    }
}
