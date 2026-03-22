import Foundation
import Testing
@testable import OracleOS

@Suite("Search — Candidate")
struct CandidateTests {

    @Test("Candidate has unique ID by default")
    func candidateDefaultID() {
        let schema = ActionSchema(name: "click_Send", kind: .click)
        let c1 = Candidate(hypothesis: "test", schema: schema, source: .memory)
        let c2 = Candidate(hypothesis: "test", schema: schema, source: .memory)
        #expect(c1.id != c2.id)
    }

    @Test("Candidate preserves source tag")
    func candidateSourceTag() {
        let schema = ActionSchema(name: "run_tests", kind: .runTests)
        let memory = Candidate(hypothesis: "h", schema: schema, source: .memory)
        let graph = Candidate(hypothesis: "h", schema: schema, source: .graph)
        let llm = Candidate(hypothesis: "h", schema: schema, source: .llmFallback)
        #expect(memory.source == .memory)
        #expect(graph.source == .graph)
        #expect(llm.source == .llmFallback)
    }

    @Test("CandidateSource raw values are stable")
    func candidateSourceRawValues() {
        #expect(CandidateSource.memory.rawValue == "memory")
        #expect(CandidateSource.graph.rawValue == "graph")
        #expect(CandidateSource.llmFallback.rawValue == "llm_fallback")
    }
}
