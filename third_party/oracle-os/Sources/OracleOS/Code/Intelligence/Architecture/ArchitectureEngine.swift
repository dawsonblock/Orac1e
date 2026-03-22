import Foundation

public final class ArchitectureEngine: @unchecked Sendable {
    private let dependencyAnalyzer: DependencyAnalyzer
    private let impactAnalyzer: ChangeImpactAnalyzer
    private let invariantChecker: InvariantChecker
    private let refactorPlanner: RefactorPlanner

    public init(
        dependencyAnalyzer: DependencyAnalyzer = DependencyAnalyzer(),
        impactAnalyzer: ChangeImpactAnalyzer = ChangeImpactAnalyzer(),
        invariantChecker: InvariantChecker = InvariantChecker(),
        refactorPlanner: RefactorPlanner = RefactorPlanner()
    ) {
        self.dependencyAnalyzer = dependencyAnalyzer
        self.impactAnalyzer = impactAnalyzer
        self.invariantChecker = invariantChecker
        self.refactorPlanner = refactorPlanner
    }

    public func review(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        candidatePaths: [String]
    ) -> ArchitectureReview {
        let highImpact = impactAnalyzer.shouldReview(goalDescription: goalDescription, candidatePaths: candidatePaths)
        let affectedModules = impactAnalyzer.affectedModules(for: candidatePaths)
        let moduleGraph = ArchitectureModuleGraph.build(from: snapshot)

        guard highImpact else {
            return ArchitectureReview(
                triggered: false,
                affectedModules: affectedModules,
                findings: [],
                refactorProposal: nil,
                riskScore: 0,
                governanceReport: .empty
            )
        }

        let dependencyFindings = dependencyAnalyzer.findings(in: moduleGraph)
        let governanceReport = invariantChecker.report(
            goalDescription: goalDescription,
            affectedModules: affectedModules,
            candidatePaths: candidatePaths,
            snapshot: snapshot
        )
        let governanceFindings = governanceReport.violations.map { $0.asArchitectureFinding() }
        let findings = (dependencyFindings + governanceFindings)
            .sorted { lhs, rhs in lhs.riskScore > rhs.riskScore }
        let proposal = refactorPlanner.proposal(from: findings)
        let riskScore = findings.map(\.riskScore).max() ?? 0.25

        return ArchitectureReview(
            triggered: true,
            affectedModules: affectedModules,
            findings: findings,
            refactorProposal: proposal,
            riskScore: riskScore,
            governanceReport: governanceReport
        )
    }

    public func reviewCandidatePatch(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        candidate: CandidatePatch,
        diffSummary: String
    ) -> ArchitectureReview {
        let baseReview = review(
            goalDescription: goalDescription,
            snapshot: snapshot,
            candidatePaths: [candidate.workspaceRelativePath]
        )
        let heuristicFindings = candidateHeuristicFindings(
            goalDescription: goalDescription,
            candidate: candidate,
            diffSummary: diffSummary
        )
        let findings = (baseReview.findings + heuristicFindings)
            .sorted { lhs, rhs in lhs.riskScore > rhs.riskScore }
        let proposal = baseReview.refactorProposal ?? refactorPlanner.proposal(from: findings)
        let riskScore = findings.map(\.riskScore).max() ?? baseReview.riskScore

        return ArchitectureReview(
            triggered: baseReview.triggered || !heuristicFindings.isEmpty,
            affectedModules: Array(Set(baseReview.affectedModules + heuristicFindings.flatMap(\.affectedModules))).sorted(),
            findings: findings,
            refactorProposal: proposal,
            riskScore: riskScore,
            governanceReport: baseReview.governanceReport
        )
    }

    private func candidateHeuristicFindings(
        goalDescription: String,
        candidate: CandidatePatch,
        diffSummary: String
    ) -> [ArchitectureFinding] {
        let loweredGoal = goalDescription.lowercased()
        let path = candidate.workspaceRelativePath
        let affectedModules = [ArchitectureModuleGraph.moduleName(for: path)]
        var findings: [ArchitectureFinding] = []

        if path.hasPrefix("Tests/"),
           loweredGoal.contains("fix") || loweredGoal.contains("repair") || loweredGoal.contains("failing")
                || loweredGoal.contains("build") || loweredGoal.contains("test")
        {
            findings.append(
                ArchitectureFinding(
                    title: "Test-only repair path",
                    summary: "This candidate changes tests instead of production code for a repair task, which risks locking in the wrong behavior.",
                    severity: .warning,
                    affectedModules: affectedModules,
                    evidence: [path],
                    riskScore: 0.65
                )
            )
        }

        if path.hasPrefix("Sources/"),
           !loweredGoal.contains("refactor"),
           candidate.content.contains("public ")
        {
            findings.append(
                ArchitectureFinding(
                    title: "Public interface change",
                    summary: "This candidate alters public surface area during a repair task. Prefer smaller internal fixes when possible.",
                    severity: .warning,
                    affectedModules: affectedModules,
                    evidence: [path],
                    riskScore: 0.45
                )
            )
        }

        if touchedFileCount(diffSummary) > 1 {
            findings.append(
                ArchitectureFinding(
                    title: "Expanded patch blast radius",
                    summary: "This candidate touches multiple files. Wider patch surfaces should be justified before they outrank safer focused fixes.",
                    severity: .warning,
                    affectedModules: affectedModules,
                    evidence: diffSummary.split(separator: "\n").map(String.init),
                    riskScore: 0.4
                )
            )
        }

          if path.contains("/Planning/") || path.contains("Sources/OracleOS/Planning/"),
           candidate.content.contains("execute(") || candidate.content.contains("WorkspaceRunner(")
        {
            findings.append(
                ArchitectureFinding(
                    title: "Planner/execution boundary drift",
                    summary: "This candidate pulls execution concerns into planning code. Keep planning declarative and execution local.",
                    severity: .critical,
                    affectedModules: affectedModules,
                    evidence: [path],
                    riskScore: 0.85,
                    governanceRuleID: .hierarchicalPlanning,
                    governanceSeverity: .hardFail
                )
            )
        }

        return findings
    }

    private func touchedFileCount(_ diffSummary: String) -> Int {
        diffSummary
            .split(separator: "\n")
            .filter { $0.contains("|") }
            .count
    }
}
