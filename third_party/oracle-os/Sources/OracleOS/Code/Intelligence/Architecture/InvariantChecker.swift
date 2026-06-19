import Foundation

public struct InvariantChecker: Sendable {
    public init() {}

    public func report(
        goalDescription: String,
        affectedModules: [String],
        candidatePaths: [String],
        snapshot: RepositorySnapshot
    ) -> GovernanceReport {
        var violations: [GovernanceViolation] = []
        let moduleSet = Set(affectedModules)
        let loweredGoal = goalDescription.lowercased()
        let hasTests = candidatePaths.contains { $0.hasPrefix("Tests/") }

        let touchesPlanning = candidatePaths.contains { $0.contains("/Planning/") }
        let touchesExecution = candidatePaths.contains { $0.contains("/Execution/") }
        let touchesLoop = candidatePaths.contains { $0.contains("/Execution/Loop/AgentLoop.swift") }
        let touchesExperiments = candidatePaths.contains { $0.contains("/Execution/Experiments/") }
        let touchesArchitecture = candidatePaths.contains { $0.contains("/Code/Intelligence/Architecture/") }
        let touchesRanking = candidatePaths.contains {
            $0.contains("/Search/Ranking/") || $0.contains("/WorldModel/WorldQuery.swift")
        }
        let touchesRecovery = candidatePaths.contains { $0.contains("/Recovery/") }
        let touchesGraph = candidatePaths.contains { $0.contains("/WorldModel/Graph/") }
        let touchesSkillLayer = candidatePaths.contains { $0.contains("/Skills/") }

        if touchesPlanning, touchesExecution {
            violations.append(
                GovernanceViolation(
                    ruleID: .hierarchicalPlanning,
                    severity: .hardFail,
                    title: "Planning/execution boundary drift",
                    summary: "Changes touch both planning and execution layers. Keep execution semantics out of planner code.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["planner", "executor"]
                )
            )
        }

        if touchesLoop && (touchesExperiments || touchesArchitecture || touchesRanking || touchesPlanning)
        {
            violations.append(
                GovernanceViolation(
                    ruleID: .executionTruthPath,
                    severity: .hardFail,
                    title: "Loop orchestration drift",
                    summary: "AgentLoop changes are coupled to subsystem internals. Keep the loop orchestration-only and route subsystem work through dedicated coordinators.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        }

          if touchesExecution,
              candidatePaths.contains(where: { $0.contains("/Intent/Policies/") }),
           !moduleSet.contains("Runtime")
        {
            violations.append(
                GovernanceViolation(
                    ruleID: .executionTruthPath,
                    severity: .hardFail,
                    title: "Execution truth path bypass risk",
                    summary: "Policy changes are reaching execution internals without the runtime boundary in scope.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["policy", "executor"]
                )
            )
        }

        if moduleSet.contains("Runtime"), moduleSet.contains("Core/Execution"), loweredGoal.contains("policy") {
            violations.append(
                GovernanceViolation(
                    ruleID: .executionTruthPath,
                    severity: .advisory,
                    title: "Policy/execution boundary drift",
                    summary: "Policy changes are crossing into execution internals. Keep policy enforcement in runtime/loop layers.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["runtime", "executor", "policy"]
                )
            )
        }

        let touchesTargetBearingSkill = candidatePaths.contains { path in
            path.contains("Skills/OS/ClickSkill.swift")
                || path.contains("Skills/OS/TypeSkill.swift")
        }
        let touchesRankingPath = touchesRanking
        if touchesTargetBearingSkill, !touchesRankingPath {
            violations.append(
                GovernanceViolation(
                    ruleID: .hierarchicalPlanning,
                    severity: .hardFail,
                    title: "Target resolution bypass risk",
                    summary: "Target-bearing OS skills changed without ranking or world-query changes in scope. Ranking bypass is not allowed.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        } else if touchesPlanning,
                  (touchesRanking || candidatePaths.contains(where: { $0.contains("/Code/Execution/") }))
        {
            violations.append(
                GovernanceViolation(
                    ruleID: .hierarchicalPlanning,
                    severity: .hardFail,
                    title: "Planner/local-resolution boundary drift",
                    summary: "Planner changes are crossing into ranking, world-query, or command-execution layers. Planners choose structure; local resolvers choose concrete actions.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        } else if touchesSkillLayer, touchesRanking, loweredGoal.contains("click") {
            violations.append(
                GovernanceViolation(
                    ruleID: .hierarchicalPlanning,
                    severity: .advisory,
                    title: "Skill/ranking integrity check",
                    summary: "Target-bearing skills must continue to resolve through ranking instead of direct element selection.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["skills", "ranking"]
                )
            )
        }

        if (touchesGraph && touchesExperiments)
            || (touchesGraph && touchesRecovery)
        {
            violations.append(
                GovernanceViolation(
                    ruleID: .reusableKnowledge,
                    severity: .hardFail,
                    title: "Trust-tier promotion drift",
                    summary: "Experiment or recovery changes are touching graph persistence paths. Keep evidence tiers separated from stable control knowledge.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        }

          if touchesRecovery,
           !moduleSet.contains("Runtime"),
              !touchesGraph
        {
            violations.append(
                GovernanceViolation(
                    ruleID: .recoveryMode,
                    severity: .advisory,
                    title: "Recovery path drift",
                    summary: "Recovery logic is changing without runtime or graph tagging in scope. Keep recovery as a first-class tracked mode.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        }

        if touchesRecovery, touchesGraph {
            violations.append(
                GovernanceViolation(
                    ruleID: .recoveryMode,
                    severity: .hardFail,
                    title: "Recovery tagging must remain explicit",
                    summary: "Recovery code is touching graph behavior directly. Recovery transitions must stay tagged and separate from nominal control knowledge.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        }

        if ChangeImpactAnalyzer().shouldReview(goalDescription: goalDescription, candidatePaths: candidatePaths), !hasTests {
            violations.append(
                GovernanceViolation(
                    ruleID: .evalBeforeGrowth,
                    severity: .hardFail,
                    title: "Architecture growth without eval coverage",
                    summary: "High-impact architectural work must add or update evals or governance tests in the same change.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: candidatePaths
                )
            )
        }

        if !DependencyAnalyzer().findCycles(in: ArchitectureModuleGraph.build(from: snapshot)).isEmpty {
            violations.append(
                GovernanceViolation(
                    ruleID: .evalBeforeGrowth,
                    severity: .advisory,
                    title: "Dependency cycle requires governance follow-up",
                    summary: "Dependency cycles increase architectural risk and should be covered by governance tests or cleanup plans.",
                    affectedModules: Array(moduleSet).sorted(),
                    evidence: ["dependency-cycle"]
                )
            )
        }

        return GovernanceReport(violations: violations)
    }
}
