import Foundation
import Testing
@testable import OracleOS

@Suite("Proposal Engine and LLM Integration")
struct ProposalEngineTests {

    // MARK: - LLM Client

    @Test("LLM client throws when no provider configured")
    func llmClientReturnsEmptyWithoutProvider() async throws {
        let client = LLMClient()
        do {
            _ = try await client.complete(LLMRequest(prompt: "test"))
            Issue.record("Expected noProvider error")
        } catch let error as LLMClientError {
            switch error {
            case .noProvider:
                break
            default:
                Issue.record("Expected noProvider error, got \(error)")
            }
        }
    }

    @Test("LLM client tracks diagnostics")
    func llmClientTracksDiagnostics() async throws {
        let provider = StubLLMProvider(response: "hello")
        let client = LLMClient(
            providers: [.planning: provider],
            defaultProvider: nil
        )

        _ = try await client.complete(LLMRequest(prompt: "test", modelTier: .planning))
        let diagnostics = client.diagnostics
        #expect(diagnostics.requestCount == 1)
        #expect(diagnostics.totalTokens > 0)
    }

    @Test("LLM client retries on failure")
    func llmClientRetriesOnFailure() async throws {
        let provider = FailingLLMProvider(failCount: 1)
        let client = LLMClient(
            providers: [.planning: provider],
            maxRetries: 2
        )

        let response = try await client.complete(LLMRequest(prompt: "test", modelTier: .planning))
        #expect(response.text == "recovered")
    }

    @Test("LLM model tier has all expected cases")
    func llmModelTierCases() {
        let tiers: [LLMModelTier] = [
            .planning, .codeRepair, .browserReasoning,
            .recovery, .memorySummarization, .metaReasoning
        ]
        #expect(tiers.count == 6)
    }

    // MARK: - Reasoning Parser

    @Test("ReasoningParser parses plan blocks from structured text")
    func reasoningParserParsesPlanBlocks() {
        let text = """
        PLAN 1
        steps:
        - run tests
        - apply patch
        risk: low
        confidence: 0.75

        PLAN 2
        steps:
        - build
        - rerun tests
        risk: medium
        confidence: 0.55
        """

        let plans = ReasoningParser.parsePlans(from: text)
        #expect(plans.count == 2)
        #expect(plans[0].steps.contains(.runTests))
        #expect(plans[0].steps.contains(.applyPatch))
        #expect(plans[0].confidence == 0.75)
        #expect(plans[0].risk == "low")
        #expect(plans[1].steps.contains(.buildProject))
        #expect(plans[1].confidence == 0.55)
    }

    @Test("ReasoningParser converts parsed plans to plan candidates")
    func reasoningParserConvertsToPlanCandidates() {
        let state = makeCodeReasoningState()
        let parsed = [
            ParsedPlan(steps: [.runTests, .applyPatch], confidence: 0.8, risk: "low"),
            ParsedPlan(steps: [.buildProject], confidence: 0.6, risk: "medium"),
        ]

        let candidates = ReasoningParser.toPlanCandidates(parsedPlans: parsed, state: state)
        #expect(candidates.count == 2)
        #expect(candidates[0].operators.count == 2)
        #expect(candidates[0].successProbability == 0.8)
        #expect(candidates[1].operators.count == 1)
    }

    @Test("ReasoningParser handles empty or malformed input")
    func reasoningParserHandlesEmptyInput() {
        let empty = ReasoningParser.parsePlans(from: "")
        #expect(empty.isEmpty)

        let malformed = ReasoningParser.parsePlans(from: "random text without plans")
        #expect(malformed.isEmpty)
    }

    @Test("ReasoningParser filters operators that fail preconditions")
    func reasoningParserFiltersInvalidOperators() {
        let state = makeOSReasoningState()
        let parsed = [
            ParsedPlan(steps: [.runTests], confidence: 0.8),
        ]
        // OS state should not allow run_tests (requires code agent kind)
        let candidates = ReasoningParser.toPlanCandidates(parsedPlans: parsed, state: state)
        #expect(candidates.isEmpty)
    }

    // MARK: - Plan Source Types

    @Test("PlanSourceType includes llm and recovery cases")
    func planSourceTypeIncludesLLMAndRecovery() {
        let llm = PlanSourceType.llm
        let recovery = PlanSourceType.recovery
        #expect(llm.rawValue == "llm")
        #expect(recovery.rawValue == "recovery")
    }

    @Test("PlanScore computes total correctly with all components")
    func planScoreComputesTotalCorrectly() {
        let score = PlanScore(
            predictedSuccess: 0.7,
            workflowMatch: 0.2,
            stableGraphSupport: 0.1,
            memoryBias: 0.05,
            riskPenalty: 0.1,
            costPenalty: 0.05,
            sourceType: .llm
        )
        #expect(score.total == 0.7 + 0.2 + 0.1 + 0.05 - 0.1 - 0.05)
        #expect(score.sourceType == .llm)
    }

    // MARK: - Helpers

    private func makeCodeReasoningState() -> ReasoningPlanningState {
        let taskContext = TaskContext.from(
            goal: Goal(description: "fix tests", workspaceRoot: "/tmp/ws", preferredAgentKind: .code),
            workspaceRoot: URL(fileURLWithPath: "/tmp/ws", isDirectory: true)
        )
        let worldState = WorldState(
            observationHash: "ws-state",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "workspace|dirty"),
                clusterKey: StateClusterKey(rawValue: "workspace|dirty"),
                appID: "Workspace",
                domain: nil,
                windowClass: nil,
                taskPhase: "engineering",
                focusedRole: nil,
                modalClass: nil,
                navigationClass: nil,
                controlContext: nil
            ),
            observation: Observation(app: "Workspace", windowTitle: "Workspace", url: nil, focusedElementID: nil, elements: []),
            repositorySnapshot: RepositorySnapshot(
                id: "repo",
                workspaceRoot: "/tmp/ws",
                buildTool: .swiftPackage,
                files: [RepositoryFile(path: "Sources/Calc.swift", isDirectory: false)],
                symbolGraph: SymbolGraph(),
                dependencyGraph: DependencyGraph(),
                testGraph: TestGraph(),
                activeBranch: "main",
                isGitDirty: true
            )
        )
        return ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: MemoryInfluence(preferredFixPath: "Sources/Calc.swift")
        )
    }

    private func makeOSReasoningState() -> ReasoningPlanningState {
        let taskContext = TaskContext.from(
            goal: Goal(description: "click submit", targetApp: "Safari", preferredAgentKind: .os)
        )
        let worldState = WorldState(
            observationHash: "safari-state",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "safari|browse"),
                clusterKey: StateClusterKey(rawValue: "safari|browse"),
                appID: "Safari",
                domain: nil,
                windowClass: nil,
                taskPhase: "browse",
                focusedRole: nil,
                modalClass: nil,
                navigationClass: nil,
                controlContext: nil
            ),
            observation: Observation(
                app: "Safari",
                windowTitle: "Safari",
                url: "https://example.com",
                focusedElementID: nil,
                elements: []
            )
        )
        return ReasoningPlanningState(
            taskContext: taskContext,
            worldState: worldState,
            memoryInfluence: MemoryInfluence()
        )
    }
}

// MARK: - Test Doubles

private final class StubLLMProvider: LLMProvider, @unchecked Sendable {
    let response: String

    init(response: String) {
        self.response = response
    }

    func complete(prompt: String) async throws -> String {
        response
    }
}

private final class FailingLLMProvider: LLMProvider, @unchecked Sendable {
    private let failCount: Int
    private var callCount = 0
    private let lock = NSLock()

    init(failCount: Int) {
        self.failCount = failCount
    }

    private func recordCall() -> Int {
        lock.lock()
        defer { lock.unlock() }
        callCount += 1
        return callCount
    }

    func complete(prompt: String) async throws -> String {
        let current = recordCall()

        if current <= failCount {
            throw LLMClientError.timeout
        }
        return "recovered"
    }
}
