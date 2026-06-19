import Foundation

/// Conservative promotion policy for workflows.
///
/// Requires **repeated critic-confirmed success** across distinct episodes
/// before promoting a workflow.  This prevents weak or noisy evidence from
/// destabilizing the planner.
///
/// Disabled by design:
/// - Auto workflow rewrite from single episodes
/// - Recipe mutation from sparse evidence
/// - Planner policy mutation from unvalidated traces
public struct WorkflowPromotionPolicy: Sendable {
    public let minimumTraceSegmentCount: Int
    public let minimumSuccessRate: Double
    public let minimumReplayValidationSuccess: Double
    public let minimumDistinctEpisodes: Int

    public init(
        minimumTraceSegmentCount: Int = 3,
        minimumSuccessRate: Double = 0.8,
        minimumReplayValidationSuccess: Double = 0.66,
        minimumDistinctEpisodes: Int = 2
    ) {
        self.minimumTraceSegmentCount = minimumTraceSegmentCount
        self.minimumSuccessRate = minimumSuccessRate
        self.minimumReplayValidationSuccess = minimumReplayValidationSuccess
        self.minimumDistinctEpisodes = minimumDistinctEpisodes
    }

    public func shouldPromote(_ plan: WorkflowPlan) -> Bool {
        guard plan.repeatedTraceSegmentCount >= minimumTraceSegmentCount else {
            return false
        }
        guard plan.successRate >= minimumSuccessRate else {
            return false
        }
        guard plan.replayValidationSuccess >= minimumReplayValidationSuccess else {
            return false
        }
        guard distinctEpisodeCount(plan) >= minimumDistinctEpisodes else {
            return false
        }
        guard !plan.evidenceTiers.contains(.recovery), !plan.evidenceTiers.contains(.experiment) else {
            return false
        }
        guard !containsUntypedEpisodeResidue(plan) else {
            return false
        }
        return true
    }

    private func episodeKey(from ref: String) -> String? {
        let parts = ref.split(separator: ":")
        guard !parts.isEmpty else { return nil }

        // Prefer using the first two components (e.g. session + task) when available
        let keyParts = parts.prefix(2).map(String.init)
        return keyParts.joined(separator: ":")
    }

    private func distinctEpisodeCount(_ plan: WorkflowPlan) -> Int {
        let episodeKeys = Set(plan.sourceTraceRefs.compactMap { ref in
            episodeKey(from: ref)
        })
        return episodeKeys.count
    }

    private func containsUntypedEpisodeResidue(_ plan: WorkflowPlan) -> Bool {
        let parameterPrefixes = Set(plan.parameterSlots.compactMap { $0.split(separator: "_").first.map(String.init) })
        let inspectedTexts = [
            plan.goalPattern,
        ] + plan.steps.flatMap { step in
            [
                step.actionContract.workspaceRelativePath,
                step.actionContract.targetLabel,
                step.semanticQuery?.text,
            ].compactMap { $0 } + step.notes
        }

        let containsTempPath = inspectedTexts.contains {
            $0.contains("/tmp/")
                || $0.contains("/private/var/")
                || $0.contains("/var/folders/")
                || $0.contains("/.oracle/experiments/")
                || $0.contains("/Users/")
        }
        if containsTempPath, !parameterPrefixes.contains("path"), !parameterPrefixes.contains("repository") {
            return true
        }

        let uuidLikePattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        if inspectedTexts.contains(where: { $0.range(of: uuidLikePattern, options: .regularExpression) != nil }),
           parameterPrefixes.isEmpty
        {
            return true
        }

        let obviousSandboxResidue = inspectedTexts.contains {
            $0.contains("sandbox-")
                || $0.contains("candidate-")
                || $0.contains("worktree-")
        }
        if obviousSandboxResidue, !parameterPrefixes.contains("path"), !parameterPrefixes.contains("repository") {
            return true
        }

        let parameterExamplesContainResidue = plan.parameterExamples.contains { slot, values in
            let kind = plan.parameterKinds[slot] ?? ""
            guard kind == "file-path" || kind == "repository" else {
                return false
            }
            return values.contains(where: { value in
                value.contains("/tmp/")
                    || value.contains("/private/var/")
                    || value.contains("/var/folders/")
                    || value.contains("/.oracle/experiments/")
                    || value.contains("/Users/")
            })
        }
        if parameterExamplesContainResidue {
            return true
        }

        return false
    }
}
