import Foundation

public struct RefactorPlanner: Sendable {
    public init() {}

    public func proposal(from findings: [ArchitectureFinding]) -> RefactorProposal? {
        guard !findings.isEmpty else { return nil }
        let affectedModules = Array(Set(findings.flatMap(\.affectedModules))).sorted()
        let steps = findings.map { finding in
            "Address \(finding.title.lowercased()) while preserving existing verified execution and policy boundaries."
        }
        let riskScore = findings.map(\.riskScore).max() ?? 0

        return RefactorProposal(
            title: "Architecture cleanup proposal",
            summary: "A bounded structural cleanup is recommended before further feature growth in \(affectedModules.joined(separator: ", ")).",
            affectedModules: affectedModules,
            steps: steps,
            invariantRefs: [
                "planner-separation",
                "policy-runtime-boundary",
                "ranking-required-for-target-resolution",
            ],
            riskScore: riskScore
        )
    }
}
