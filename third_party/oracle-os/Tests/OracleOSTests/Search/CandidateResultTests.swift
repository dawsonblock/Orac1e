import Foundation
import Testing
@testable import OracleOS

@Suite("Search — CandidateResult")
struct CandidateResultTests {

    @Test("CandidateResult records success and score")
    func resultRecordsSuccessAndScore() {
        let candidate = Candidate(
            hypothesis: "test",
            schema: ActionSchema(name: "click_Send", kind: .click),
            source: .memory
        )
        let result = CandidateResult(
            candidate: candidate,
            success: true,
            score: 0.95,
            criticOutcome: .success,
            elapsedMs: 120
        )
        #expect(result.success == true)
        #expect(result.score == 0.95)
        #expect(result.criticOutcome == .success)
        #expect(result.elapsedMs == 120)
    }

    @Test("CandidateResult records failure")
    func resultRecordsFailure() {
        let candidate = Candidate(
            hypothesis: "test",
            schema: ActionSchema(name: "build_project", kind: .buildProject),
            source: .graph
        )
        let result = CandidateResult(
            candidate: candidate,
            success: false,
            score: 0.0,
            criticOutcome: .failure,
            notes: ["build failed"]
        )
        #expect(result.success == false)
        #expect(result.criticOutcome == .failure)
        #expect(result.notes == ["build failed"])
    }
}
