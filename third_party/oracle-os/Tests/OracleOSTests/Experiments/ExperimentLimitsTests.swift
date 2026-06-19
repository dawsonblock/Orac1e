import Testing
@testable import OracleOS

@Suite("Experiment Limits")
struct ExperimentLimitsTests {

    @Test("ExperimentLimits defines max candidates")
    func maxCandidatesIsDefined() {
        #expect(ExperimentLimits.maxCandidates == 5)
    }

    @Test("ExperimentLimits defines max iterations")
    func maxIterationsIsDefined() {
        #expect(ExperimentLimits.maxIterations == 3)
    }

    @Test("ExperimentSpec.boundedByLimits truncates excess candidates")
    func boundedByLimitsTruncatesCandidates() {
        let candidates = (0..<10).map { makeCandidatePatch(id: "patch-\($0)") }
        let spec = ExperimentSpec(
            goalDescription: "fix test",
            workspaceRoot: "/tmp/ws",
            candidates: candidates
        )

        let bounded = spec.boundedByLimits()
        #expect(bounded.candidates.count == ExperimentLimits.maxCandidates)
    }

    @Test("ExperimentSpec.boundedByLimits keeps small candidate lists unchanged")
    func boundedByLimitsKeepsSmallLists() {
        let candidates = [makeCandidatePatch(id: "patch-0")]
        let spec = ExperimentSpec(
            goalDescription: "fix test",
            workspaceRoot: "/tmp/ws",
            candidates: candidates
        )

        let bounded = spec.boundedByLimits()
        #expect(bounded.candidates.count == 1)
    }

    private func makeCandidatePatch(id: String) -> CandidatePatch {
        CandidatePatch(
            id: id,
            title: "Fix \(id)",
            summary: "Test patch",
            workspaceRelativePath: "Sources/Test.swift",
            content: "+// fix"
        )
    }
}
