import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Graph Aware Loop")
struct GraphAwareLoopTests {

    @Test("GraphStore persists eligible stable edges and action contracts")
    func graphStorePersistsStableEdges() {
        let dbURL = makeTempGraphURL()
        let store = GraphStore(databaseURL: dbURL)
        let fromState = planningState(
            id: "chrome|gmail|browse",
            appID: "Google Chrome",
            domain: "mail.google.com",
            taskPhase: "browse"
        )
        let toState = planningState(
            id: "chrome|gmail|compose",
            appID: "Google Chrome",
            domain: "mail.google.com",
            taskPhase: "compose"
        )
        let contract = ActionContract(
            id: "click|AXButton|Compose|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Compose",
            locatorStrategy: "query"
        )

        for _ in 0..<5 {
            store.recordTransition(
                transition(
                    from: fromState.id,
                    to: toState.id,
                    actionContractID: contract.id,
                    verified: true
                ),
                actionContract: contract,
                fromState: fromState,
                toState: toState
            )
        }

        let promoted = store.promoteEligibleEdges()
        #expect(promoted.count == 1)

        let reopened = GraphStore(databaseURL: dbURL)
        #expect(reopened.actionContract(for: contract.id)?.targetLabel == "Compose")
        #expect(reopened.outgoingStableEdges(from: fromState.id).count == 1)
        #expect(reopened.planningState(for: toState.id)?.taskPhase == "compose")
    }

    @Test("GraphStore records failures without promoting edge")
    func graphStoreRecordsFailureWithoutPromotion() {
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let state = planningState(
            id: "finder|rename",
            appID: "Finder",
            domain: nil,
            taskPhase: "browse"
        )
        let contract = ActionContract(
            id: "click|AXButton|Rename|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Rename",
            locatorStrategy: "query"
        )

        store.recordFailure(
            state: state,
            actionContract: contract,
            failure: .elementNotFound
        )
        _ = store.promoteEligibleEdges()

        #expect(store.allStableEdges().isEmpty)
        #expect(store.allCandidateEdges().first?.failureHistogram[FailureClass.elementNotFound.rawValue] == 1)
    }

    @Test("Promotion freezes when global verified success rate is too low")
    func promotionFreezeWhenGlobalSuccessRateLow() {
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let goodFrom = planningState(id: "good|from", appID: "Finder", domain: nil, taskPhase: "browse")
        let goodTo = planningState(id: "good|to", appID: "Finder", domain: nil, taskPhase: "rename")
        let goodContract = ActionContract(
            id: "click|AXButton|Rename|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Rename",
            locatorStrategy: "query"
        )

        for _ in 0..<5 {
            store.recordTransition(
                transition(
                    from: goodFrom.id,
                    to: goodTo.id,
                    actionContractID: goodContract.id,
                    verified: true
                ),
                actionContract: goodContract,
                fromState: goodFrom,
                toState: goodTo
            )
        }

        let failureState = planningState(id: "bad|state", appID: "Finder", domain: nil, taskPhase: "browse")
        let failureContract = ActionContract(
            id: "click|AXButton|Delete|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Delete",
            locatorStrategy: "query"
        )
        for _ in 0..<6 {
            store.recordFailure(
                state: failureState,
                actionContract: failureContract,
                failure: .actionFailed
            )
        }

        let promoted = store.promoteEligibleEdges()
        #expect(promoted.isEmpty)
        #expect(store.allStableEdges().isEmpty)
    }

    @Test("Stable edges demote after repeated failures")
    func stableEdgesDemoteAfterFailures() {
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let fromState = planningState(id: "gmail|browse", appID: "Google Chrome", domain: "mail.google.com", taskPhase: "browse")
        let toState = planningState(id: "gmail|compose", appID: "Google Chrome", domain: "mail.google.com", taskPhase: "compose")
        let contract = ActionContract(
            id: "click|AXButton|Compose|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Compose",
            locatorStrategy: "query"
        )

        for _ in 0..<5 {
            store.recordTransition(
                transition(
                    from: fromState.id,
                    to: toState.id,
                    actionContractID: contract.id,
                    verified: true
                ),
                actionContract: contract,
                fromState: fromState,
                toState: toState
            )
        }
        _ = store.promoteEligibleEdges()
        #expect(store.allStableEdges().count == 1)

        for _ in 0..<5 {
            store.recordTransition(
                transition(
                    from: fromState.id,
                    to: toState.id,
                    actionContractID: contract.id,
                    verified: false,
                    failureClass: .verificationFailed
                ),
                actionContract: contract,
                fromState: fromState,
                toState: toState
            )
        }

        let removed = store.pruneOrDemoteEdges()
        #expect(removed == [store.allCandidateEdges().first?.edgeID].compactMap { $0 })
        #expect(store.allStableEdges().isEmpty)
    }

    @Test("ClickSkill fails on ambiguous targets instead of picking first element")
    func clickSkillFailsOnAmbiguousTargets() {
        let observation = Observation(
            app: "Google Chrome",
            windowTitle: "Compose - Gmail",
            url: "https://mail.google.com/mail/u/0/#inbox?compose=new",
            focusedElementID: nil,
            elements: [
                UnifiedElement(id: "send-primary", source: .ax, role: "AXButton", label: "Send", confidence: 0.95),
                UnifiedElement(id: "send-secondary", source: .ax, role: "AXButton", label: "Send", confidence: 0.94),
            ]
        )
        let state = WorldState(observation: observation)
        let skill = ClickSkill()

        do {
            _ = try skill.resolve(
                query: ElementQuery(text: "Send", clickable: true),
                state: state,
                memoryStore: UnifiedMemoryStore()
            )
            Issue.record("Expected ambiguous target error")
        } catch let error as SkillResolutionError {
            #expect(error.failureClass == .elementAmbiguous)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("AgentLoop submits exactly one intent through orchestrator")
    func agentLoopSubmitsOneIntentThroughOrchestrator() async throws {
        let intent = Intent(
            domain: .ui,
            objective: "open gmail compose",
            metadata: [
                "app": "Google Chrome",
                "targetTaskPhase": "compose",
            ]
        )
        let orchestrator = RecordingIntentAPI()
        let loop = AgentLoop(
            intake: QueueIntentSource([intent]),
            orchestrator: orchestrator
        )

        let task = Task { await loop.run() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        loop.stop()
        _ = await task.result

        let submitted = await orchestrator.submittedIntents()
        #expect(submitted.count == 1)
        #expect(submitted.first?.objective == "open gmail compose")
        #expect(submitted.first?.metadata["app"] == "Google Chrome")
        #expect(submitted.first?.metadata["targetTaskPhase"] == "compose")
    }

    @Test("AgentLoop keeps delegating through orchestrator even when responses fail")
    func agentLoopDelegatesFailedResponsesThroughOrchestrator() async {
        let intentID = UUID()
        let orchestrator = RecordingIntentAPI(
            fixedResponse: IntentResponse(
                intentID: intentID,
                outcome: .failed,
                summary: "Policy blocked by orchestrator",
                cycleID: UUID()
            )
        )
        let loop = AgentLoop(
            intake: QueueIntentSource([
                Intent(
                    id: intentID,
                    domain: .ui,
                    objective: "continue terminal task",
                    metadata: [
                        "app": "Terminal",
                        "targetTaskPhase": "shell",
                    ]
                ),
            ]),
            orchestrator: orchestrator
        )

        let task = Task { await loop.run() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        loop.stop()
        _ = await task.result

        let submitted = await orchestrator.submittedIntents()
        #expect(submitted.count == 1)
        #expect(submitted.first?.objective == "continue terminal task")
    }

    @Test("AgentLoop idles without submitting when intake is empty")
    func agentLoopDoesNotSubmitWhenIntakeIsEmpty() async {
        let orchestrator = RecordingIntentAPI()
        let loop = AgentLoop(
            intake: QueueIntentSource([]),
            orchestrator: orchestrator
        )

        let task = Task { await loop.run() }
        loop.stop()
        _ = await task.result

        let submitted = await orchestrator.submittedIntents()
        #expect(submitted.isEmpty)
    }

    @Test("Planner prefers workflow retrieval before stable graph reuse")
    func plannerPrefersWorkflowBeforeStableGraph() {
        let abstraction = StateAbstraction()
        let inboxObservation = Observation(
            app: "Google Chrome",
            windowTitle: "Inbox - Gmail",
            url: "https://mail.google.com/mail/u/0/#inbox",
            focusedElementID: "compose",
            elements: [
                UnifiedElement(id: "compose", source: .ax, role: "AXButton", label: "Compose", focused: true, confidence: 0.98),
            ]
        )
        let composeObservation = Observation(
            app: "Google Chrome",
            windowTitle: "Compose - Gmail",
            url: "https://mail.google.com/mail/u/0/#inbox?compose=new",
            focusedElementID: "body",
            elements: [
                UnifiedElement(id: "body", source: .ax, role: "AXTextArea", label: "Message Body", focused: true, confidence: 0.95),
            ]
        )
        let fromState = abstraction.abstract(
            observation: inboxObservation,
            observationHash: ObservationHash.hash(inboxObservation)
        )
        let toState = abstraction.abstract(
            observation: composeObservation,
            observationHash: ObservationHash.hash(composeObservation)
        )
        let contract = ActionContract(
            id: "click|AXButton|Compose|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Compose",
            locatorStrategy: "query"
        )
        let store = GraphStore(databaseURL: makeTempGraphURL())
        for _ in 0..<5 {
            store.recordTransition(
                transition(
                    from: fromState.id,
                    to: toState.id,
                    actionContractID: contract.id,
                    verified: true
                ),
                actionContract: contract,
                fromState: fromState,
                toState: toState
            )
        }
        _ = store.promoteEligibleEdges()

        let planner = MainPlanner()
        planner.workflowIndex.add(
            WorkflowPlan(
                agentKind: .os,
                goalPattern: "open gmail compose",
                steps: [
                    WorkflowStep(
                        agentKind: .os,
                        stepPhase: .operatingSystem,
                        actionContract: contract,
                        semanticQuery: ElementQuery(
                            text: "Compose",
                            role: "AXButton",
                            clickable: true,
                            visibleOnly: true,
                            app: "Google Chrome"
                        ),
                        fromPlanningStateID: fromState.id.rawValue
                    ),
                ],
                successRate: 0.95,
                sourceTraceRefs: ["trace-1"],
                sourceGraphEdgeRefs: ["edge-1"],
                repeatedTraceSegmentCount: 3,
                replayValidationSuccess: 1,
                promotionStatus: .promoted
            )
        )
        planner.setGoal(
            Goal(
                description: "open gmail compose",
                targetApp: "Google Chrome",
                targetDomain: "mail.google.com",
                targetTaskPhase: "compose"
            )
        )

        let decision = planner.nextStep(
            worldState: WorldState(observation: inboxObservation),
            graphStore: store,
            memoryStore: UnifiedMemoryStore()
        )

        #expect(decision?.source == .workflow)
        #expect(decision?.workflowID != nil)
    }

    @Test("Planner reuses candidate graph edge before exploration")
    func plannerReusesCandidateGraphEdgeBeforeExploration() {
        let abstraction = StateAbstraction()
        let inboxObservation = Observation(
            app: "Google Chrome",
            windowTitle: "Inbox - Gmail",
            url: "https://mail.google.com/mail/u/0/#inbox",
            focusedElementID: "compose",
            elements: [
                UnifiedElement(id: "compose", source: .ax, role: "AXButton", label: "Compose", focused: true, confidence: 0.98),
            ]
        )
        let composeObservation = Observation(
            app: "Google Chrome",
            windowTitle: "Compose - Gmail",
            url: "https://mail.google.com/mail/u/0/#inbox?compose=new",
            focusedElementID: "body",
            elements: [
                UnifiedElement(id: "body", source: .ax, role: "AXTextArea", label: "Message Body", focused: true, confidence: 0.95),
            ]
        )
        let fromState = abstraction.abstract(
            observation: inboxObservation,
            observationHash: ObservationHash.hash(inboxObservation)
        )
        let toState = abstraction.abstract(
            observation: composeObservation,
            observationHash: ObservationHash.hash(composeObservation)
        )
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let contract = ActionContract(
            id: "click|AXButton|Compose|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Compose",
            locatorStrategy: "query"
        )
        for _ in 0..<2 {
            store.recordTransition(
                transition(
                    from: fromState.id,
                    to: toState.id,
                    actionContractID: contract.id,
                    verified: true
                ),
                actionContract: contract,
                fromState: fromState,
                toState: toState
            )
        }

        let planner = MainPlanner()
        planner.setGoal(
            Goal(
                description: "open gmail compose",
                targetApp: "Google Chrome",
                targetDomain: "mail.google.com",
                targetTaskPhase: "compose"
            )
        )

        let decision = planner.nextStep(
            worldState: WorldState(observation: inboxObservation),
            graphStore: store,
            memoryStore: UnifiedMemoryStore()
        )

        #expect(decision?.source == .candidateGraph)
        #expect(decision?.currentEdgeID == store.allCandidateEdges().first?.edgeID)
        #expect(decision?.fallbackReason == "workflow retrieval and stable graph path reuse were unavailable")
        #expect(decision?.graphSearchDiagnostics?.chosenPathEdgeIDs.count == 1)
    }

    @Test("Exploration decisions carry explicit fallback reasons")
    func explorationDecisionCarriesFallbackReason() {
        let planner = MainPlanner()
        planner.setGoal(
            Goal(
                description: "rename file in finder",
                targetApp: "Finder",
                targetTaskPhase: "rename"
            )
        )

        let decision = planner.nextStep(
            worldState: WorldState(
                observation: Observation(
                    app: "Finder",
                    windowTitle: "Finder",
                    url: nil,
                    focusedElementID: "rename",
                    elements: [
                        UnifiedElement(id: "rename", source: .ax, role: "AXButton", label: "Rename", confidence: 0.97),
                    ]
                )
            ),
            graphStore: GraphStore(databaseURL: makeTempGraphURL()),
            memoryStore: UnifiedMemoryStore()
        )

        #expect(decision?.source == .exploration)
        #expect(decision?.fallbackReason == "workflow retrieval, stable graph path reuse, and candidate graph reuse were unavailable")
    }

    @Test("Graph planner returns multi-step stable path before exploration")
    func graphPlannerReturnsMultiStepStablePath() {
        let store = GraphStore(databaseURL: makeTempGraphURL())
        let start = planningState(id: "gmail|inbox", appID: "Google Chrome", domain: "mail.google.com", taskPhase: "browse")
        let middle = planningState(id: "gmail|menu", appID: "Google Chrome", domain: "mail.google.com", taskPhase: "menu")
        let end = planningState(id: "gmail|compose", appID: "Google Chrome", domain: "mail.google.com", taskPhase: "compose")
        let firstContract = ActionContract(
            id: "click|AXButton|ComposeMenu|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Compose Menu",
            locatorStrategy: "query"
        )
        let secondContract = ActionContract(
            id: "click|AXButton|Compose|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Compose",
            locatorStrategy: "query"
        )

        for _ in 0..<5 {
            store.recordTransition(
                transition(
                    from: start.id,
                    to: middle.id,
                    actionContractID: firstContract.id,
                    verified: true
                ),
                actionContract: firstContract,
                fromState: start,
                toState: middle
            )
            store.recordTransition(
                transition(
                    from: middle.id,
                    to: end.id,
                    actionContractID: secondContract.id,
                    verified: true
                ),
                actionContract: secondContract,
                fromState: middle,
                toState: end
            )
        }
        _ = store.promoteEligibleEdges()

        let planner = GraphMainPlanner(maxDepth: 6, beamWidth: 5)
        let result = planner.search(
            from: start,
            goal: Goal(
                description: "open gmail compose",
                targetApp: "Google Chrome",
                targetDomain: "mail.google.com",
                targetTaskPhase: "compose",
                preferredAgentKind: .os
            ),
            graphStore: store,
            memoryStore: UnifiedMemoryStore(),
            worldState: WorldState(
                observationHash: "start-hash",
                planningState: start,
                observation: Observation(app: "Google Chrome", windowTitle: "Inbox", url: "https://mail.google.com/mail/u/0/#inbox"),
                repositorySnapshot: nil
            )
        )

        #expect(result?.edges.count == 2)
        #expect(result?.diagnostics.chosenPathEdgeIDs.count == 2)
        #expect(result?.exploredEdgeIDs.isEmpty == false)
    }

    @Test("Workflow promotion policy rejects experiment and recovery evidence")
    func workflowPromotionPolicyRejectsUntrustedEvidence() {
        let policy = WorkflowPromotionPolicy()
        let contract = ActionContract(
            id: "click|AXButton|Compose|query",
            skillName: "click",
            targetRole: "AXButton",
            targetLabel: "Compose",
            locatorStrategy: "query"
        )
        let promoted = WorkflowPlan(
            agentKind: .os,
            goalPattern: "open gmail compose",
            steps: [
                WorkflowStep(
                    agentKind: .os,
                    stepPhase: .operatingSystem,
                    actionContract: contract
                ),
            ],
            successRate: 0.9,
            sourceTraceRefs: ["session1:compose:0", "session2:compose:0", "session3:compose:0"],
            evidenceTiers: [.candidate],
            repeatedTraceSegmentCount: 3,
            replayValidationSuccess: 0.9,
            promotionStatus: .candidate
        )
        let experimental = WorkflowPlan(
            agentKind: .os,
            goalPattern: "open gmail compose",
            steps: [
                WorkflowStep(
                    agentKind: .os,
                    stepPhase: .operatingSystem,
                    actionContract: contract
                ),
            ],
            successRate: 0.95,
            sourceTraceRefs: ["session1:compose:0", "session2:compose:0", "session3:compose:0", "session4:compose:0"],
            evidenceTiers: [.experiment],
            repeatedTraceSegmentCount: 4,
            replayValidationSuccess: 0.9,
            promotionStatus: .candidate
        )

        #expect(policy.shouldPromote(promoted))
        #expect(policy.shouldPromote(experimental) == false)
    }

    private func transition(
        from: PlanningStateID,
        to: PlanningStateID,
        actionContractID: String,
        verified: Bool,
        failureClass: FailureClass? = nil
    ) -> VerifiedTransition {
        VerifiedTransition(
            fromPlanningStateID: from,
            toPlanningStateID: to,
            actionContractID: actionContractID,
            postconditionClass: .elementAppeared,
            verified: verified,
            failureClass: failureClass?.rawValue,
            latencyMs: 120
        )
    }

    private func planningState(
        id: String,
        appID: String,
        domain: String?,
        taskPhase: String?
    ) -> PlanningState {
        PlanningState(
            id: PlanningStateID(rawValue: id),
            clusterKey: StateClusterKey(rawValue: id),
            appID: appID,
            domain: domain,
            windowClass: nil,
            taskPhase: taskPhase,
            focusedRole: "AXButton",
            modalClass: nil,
            navigationClass: domain == nil ? nil : "web",
            controlContext: nil
        )
    }

    private func makeTempGraphURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("graph.sqlite3", isDirectory: false)
    }
}

private actor QueueIntentSource: IntentSource {
    private var intents: [Intent]

    init(_ intents: [Intent]) {
        self.intents = intents
    }

    func next() async -> Intent? {
        guard !intents.isEmpty else { return nil }
        return intents.removeFirst()
    }
}

private actor RecordingIntentAPI: IntentAPI {
    private let fixedResponse: IntentResponse?
    private var intents: [Intent] = []

    init(fixedResponse: IntentResponse? = nil) {
        self.fixedResponse = fixedResponse
    }

    func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        intents.append(intent)
        if let fixedResponse {
            return fixedResponse
        }
        return IntentResponse(
            intentID: intent.id,
            outcome: .success,
            summary: "Recorded intent submission",
            cycleID: UUID()
        )
    }

    func queryState() async throws -> RuntimeSnapshot {
        RuntimeSnapshot(summary: "Recorded intent API")
    }

    func submittedIntents() -> [Intent] {
        intents
    }
}
