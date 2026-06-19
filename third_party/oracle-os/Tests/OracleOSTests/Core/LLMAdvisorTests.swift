import Foundation
import Testing
@testable import OracleOS

@Suite("LLM Advisors")
struct LLMAdvisorTests {

    // MARK: - LLM Repair Advisor

    @Test("LLM repair advisor falls back to deterministic strategies without provider")
    func repairAdvisorFallsBackWithoutProvider() async {
        let client = LLMClient()
        let advisor = LLMRepairAdvisor(llmClient: client)

        let advice = await advisor.advise(
            errorSignature: "test failure in Calculator.swift",
            faultCandidates: ["Sources/Calculator.swift", "Sources/MathEngine.swift"],
            memoryInfluence: MemoryInfluence(preferredFixPath: "Sources/Calculator.swift")
        )

        #expect(!advice.strategies.isEmpty)
        #expect(advice.strategies.first?.targetPath == "Sources/Calculator.swift")
    }

    @Test("LLM repair advisor uses LLM when provider is available")
    func repairAdvisorUsesLLM() async {
        let response = """
        Strategy 1:
        description: Fix the arithmetic logic in Calculator.swift
        target: Sources/Calculator.swift
        confidence: 0.8
        effect: Resolves the test failure
        risk: low
        """
        let provider = StubLLMProvider(response: response)
        let client = LLMClient(providers: [.codeRepair: provider])
        let advisor = LLMRepairAdvisor(llmClient: client)

        let advice = await advisor.advise(
            errorSignature: "test failure",
            faultCandidates: ["Sources/Calculator.swift"],
            memoryInfluence: MemoryInfluence()
        )

        #expect(advice.diagnostics.llmUsed)
        #expect(!advice.strategies.isEmpty)
        #expect(advice.strategies.first?.targetPath == "Sources/Calculator.swift")
        #expect(advice.strategies.first?.confidence == 0.8)
    }

    // MARK: - LLM Target Resolver

    @Test("LLM target resolver returns empty without provider")
    func targetResolverReturnsEmptyWithoutProvider() async {
        let client = LLMClient()
        let resolver = LLMTargetResolver(llmClient: client)

        let result = await resolver.resolve(
            goal: "submit login form",
            domSummary: "Login page with form",
            visibleElements: ["Submit button", "Username field"]
        )

        #expect(!result.llmUsed)
        #expect(result.candidates.isEmpty)
    }

    @Test("LLM target resolver parses candidates from LLM response")
    func targetResolverParsesCandidates() async {
        let response = """
        element: Submit button
        confidence: 0.85
        reason: This is the primary form submission button

        element: Username field
        confidence: 0.3
        reason: Input field, not the target action
        """
        let provider = StubLLMProvider(response: response)
        let client = LLMClient(providers: [.browserReasoning: provider])
        let resolver = LLMTargetResolver(llmClient: client)

        let result = await resolver.resolve(
            goal: "submit form",
            domSummary: "Login page",
            visibleElements: ["Submit button", "Username field"]
        )

        #expect(result.llmUsed)
        // Only "Submit button" should pass the 0.6 confidence threshold
        #expect(result.candidates.count == 1)
        #expect(result.candidates.first?.elementDescription == "Submit button")
    }

    // MARK: - LLM Recovery Advisor

    @Test("LLM recovery advisor returns default strategies without provider")
    func recoveryAdvisorReturnsDefaultsWithoutProvider() async {
        let client = LLMClient()
        let advisor = LLMRecoveryAdvisor(llmClient: client)

        let plan = await advisor.advise(
            failureClass: .modalBlocking,
            recentActions: ["click", "navigate"],
            memoryInfluence: MemoryInfluence()
        )

        #expect(!plan.llmUsed)
        #expect(!plan.strategies.isEmpty)
        #expect(plan.strategies.first?.name == "dismiss_modal")
    }

    @Test("LLM recovery advisor returns memory-preferred strategy first")
    func recoveryAdvisorPrefersMemoryStrategy() async {
        let client = LLMClient()
        let advisor = LLMRecoveryAdvisor(llmClient: client)

        let plan = await advisor.advise(
            failureClass: .elementNotFound,
            recentActions: ["click"],
            memoryInfluence: MemoryInfluence(preferredRecoveryStrategy: "refocus_application")
        )

        #expect(plan.strategies.first?.name == "refocus_application")
    }

    @Test("LLM recovery advisor handles different failure classes")
    func recoveryAdvisorHandlesFailureClasses() async {
        let client = LLMClient()
        let advisor = LLMRecoveryAdvisor(llmClient: client)

        let modalPlan = await advisor.advise(
            failureClass: .modalBlocking,
            recentActions: [],
            memoryInfluence: MemoryInfluence()
        )
        #expect(modalPlan.strategies.contains { $0.name == "dismiss_modal" })

        let focusPlan = await advisor.advise(
            failureClass: .wrongFocus,
            recentActions: [],
            memoryInfluence: MemoryInfluence()
        )
        #expect(focusPlan.strategies.contains { $0.name == "refocus_application" })

        let buildPlan = await advisor.advise(
            failureClass: .buildFailed,
            recentActions: [],
            memoryInfluence: MemoryInfluence()
        )
        #expect(buildPlan.strategies.contains { $0.name == "revert_patch" })
    }

    @Test("LLM recovery advisor uses LLM when provider is available")
    func recoveryAdvisorUsesLLM() async {
        let response = """
        strategy: refresh_observation
        description: Refresh the page state and retry
        confidence: 0.8
        reason: Element state may have changed after navigation
        """
        let provider = StubLLMProvider(response: response)
        let client = LLMClient(providers: [.recovery: provider])
        let advisor = LLMRecoveryAdvisor(llmClient: client)

        let plan = await advisor.advise(
            failureClass: .elementNotFound,
            recentActions: ["navigate"],
            memoryInfluence: MemoryInfluence()
        )

        #expect(plan.llmUsed)
        #expect(!plan.strategies.isEmpty)
        #expect(plan.strategies.first?.name == "refresh_observation")
        #expect(plan.strategies.first?.confidence == 0.8)
    }

    // MARK: - MemoryInfluence.empty

    @Test("MemoryInfluence.empty provides default values")
    func memoryInfluenceEmptyDefaults() {
        let empty = MemoryInfluence.empty
        #expect(empty.executionRankingBias == 0)
        #expect(empty.preferredFixPath == nil)
        #expect(empty.preferredRecoveryStrategy == nil)
        #expect(empty.avoidedPaths.isEmpty)
        #expect(empty.riskPenalty == 0)
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
