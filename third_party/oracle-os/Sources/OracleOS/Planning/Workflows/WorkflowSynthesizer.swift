import Foundation

// WorkflowSynthesizer may only promote reusable, parameterized structure from
// repeated verified traces. Episode-specific residue must remain in trace or
// artifact storage unless it is explicitly lifted into typed parameters.
public struct WorkflowSynthesizer: Sendable {
    private let replayValidator: WorkflowReplayValidator
    private let promotionPolicy: WorkflowPromotionPolicy
    private let patternMiner: WorkflowPatternMiner

    public init(
        replayValidator: WorkflowReplayValidator = WorkflowReplayValidator(),
        promotionPolicy: WorkflowPromotionPolicy = WorkflowPromotionPolicy(),
        patternMiner: WorkflowPatternMiner = WorkflowPatternMiner()
    ) {
        self.replayValidator = replayValidator
        self.promotionPolicy = promotionPolicy
        self.patternMiner = patternMiner
    }

    public func synthesize(
        goalPattern: String,
        events: [TraceEvent]
    ) -> [WorkflowPlan] {
        patternMiner.mine(events: events)
            .map { candidatePlan(goalPattern: goalPattern, pattern: $0) }
            .sorted { lhs, rhs in
                if lhs.successRate == rhs.successRate {
                    return lhs.goalPattern < rhs.goalPattern
                }
                return lhs.successRate > rhs.successRate
            }
    }

    private func candidatePlan(
        goalPattern: String,
        pattern: WorkflowPattern
    ) -> WorkflowPlan {
        let group = RepeatedTraceSegment(
            fingerprint: pattern.fingerprint,
            segments: pattern.segments
        )
        let representative = group.segments[0]
        let parameters = ParameterExtractor.extract(from: group.segments)
        let steps = representative.events.enumerated().map { index, event in
            step(
                from: event,
                stepIndex: index,
                parameters: parameters,
                stablePlanningStateID: stablePlanningStateID(for: group, stepIndex: index)
            )
        }
        let parameterKinds = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.kind) })
        let parameterExamples = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.values) })
        let replayValidationSuccess = replayValidator.validate(
            plan: WorkflowPlan(
                agentKind: representative.agentKind,
                goalPattern: goalPattern,
                steps: steps,
                parameterSlots: parameters.map(\.name),
                parameterKinds: parameterKinds,
                parameterExamples: parameterExamples,
                successRate: successRate(for: group),
                sourceTraceRefs: sourceTraceRefs(for: group),
                sourceGraphEdgeRefs: sourceGraphEdgeRefs(for: group),
                evidenceTiers: representative.evidenceTiers,
                repeatedTraceSegmentCount: group.segments.count
            ),
            against: group.segments
        )

        let basePlan = WorkflowPlan(
            agentKind: representative.agentKind,
            goalPattern: goalPattern,
            steps: steps,
            parameterSlots: parameters.map(\.name),
            parameterKinds: parameterKinds,
            parameterExamples: parameterExamples,
            successRate: successRate(for: group),
            sourceTraceRefs: sourceTraceRefs(for: group),
            sourceGraphEdgeRefs: sourceGraphEdgeRefs(for: group),
            evidenceTiers: combinedEvidenceTiers(for: group),
            repeatedTraceSegmentCount: group.segments.count,
            replayValidationSuccess: replayValidationSuccess,
            promotionStatus: .candidate,
            lastValidatedAt: Date(),
            lastSucceededAt: latestTimestamp(for: group)
        )

        return WorkflowPlan(
            id: basePlan.id,
            agentKind: basePlan.agentKind,
            goalPattern: basePlan.goalPattern,
            steps: basePlan.steps,
            parameterSlots: basePlan.parameterSlots,
            parameterKinds: basePlan.parameterKinds,
            parameterExamples: basePlan.parameterExamples,
            successRate: basePlan.successRate,
            sourceTraceRefs: basePlan.sourceTraceRefs,
            sourceGraphEdgeRefs: basePlan.sourceGraphEdgeRefs,
            evidenceTiers: basePlan.evidenceTiers,
            repeatedTraceSegmentCount: basePlan.repeatedTraceSegmentCount,
            replayValidationSuccess: basePlan.replayValidationSuccess,
            promotionStatus: promotionPolicy.shouldPromote(basePlan) ? .promoted : .candidate,
            lastValidatedAt: basePlan.lastValidatedAt,
            lastSucceededAt: basePlan.lastSucceededAt
        )
    }

    private func step(
        from event: TraceEvent,
        stepIndex: Int,
        parameters: [ExtractedParameter],
        stablePlanningStateID: String?
    ) -> WorkflowStep {
        let agentKind = AgentKind(rawValue: event.agentKind ?? AgentKind.os.rawValue) ?? .os
        let parameterizedTarget = ParameterExtractor.applySlots(
            to: event.actionTarget ?? event.selectedElementLabel,
            parameters: parameters,
            stepIndex: stepIndex
        )
        let parameterizedPath = ParameterExtractor.applySlots(
            to: event.workspaceRelativePath,
            parameters: parameters,
            stepIndex: stepIndex
        )
        let semanticQuery: ElementQuery?
        if agentKind == .os {
            semanticQuery = ElementQuery(
                text: parameterizedTarget,
                role: nil,
                editable: event.actionName == "type" || event.actionName == "fill_form",
                clickable: event.actionName == "click" || event.actionName == "read_file",
                visibleOnly: true,
                app: nil
            )
        } else {
            semanticQuery = nil
        }

        let actionContract = ActionContract(
            id: event.actionContractID ?? [
                agentKind.rawValue,
                event.actionName,
                parameterizedPath ?? parameterizedTarget ?? "none",
            ].joined(separator: "|"),
            agentKind: agentKind,
            skillName: event.actionName,
            targetRole: nil,
            targetLabel: parameterizedTarget,
            locatorStrategy: event.selectedElementID == nil ? "query" : "dom-id",
            workspaceRelativePath: parameterizedPath,
            commandCategory: event.commandCategory,
            plannerFamily: event.plannerFamily
        )

        return WorkflowStep(
            agentKind: agentKind,
            stepPhase: taskPhase(for: event),
            actionContract: actionContract,
            semanticQuery: semanticQuery,
            fromPlanningStateID: stablePlanningStateID,
            notes: [
                event.postconditionClass.map { "postcondition=\($0)" },
                ParameterExtractor.applySlots(
                    to: event.commandSummary,
                    parameters: parameters,
                    stepIndex: stepIndex
                ),
            ].compactMap { $0 }
        )
    }

    private func successRate(for group: RepeatedTraceSegment) -> Double {
        let totalEvents = group.segments.flatMap(\.events)
        guard !totalEvents.isEmpty else { return 0 }
        let successes = totalEvents.filter(\.success).count
        return Double(successes) / Double(totalEvents.count)
    }

    private func sourceTraceRefs(for group: RepeatedTraceSegment) -> [String] {
        group.segments.flatMap { segment in
            segment.events.map { "\($0.sessionID):\($0.stepID)" }
        }
    }

    private func sourceGraphEdgeRefs(for group: RepeatedTraceSegment) -> [String] {
        Array(
            Set(
                group.segments.flatMap { segment in
                    segment.events.flatMap { event in
                        ([event.currentEdgeID] + (event.pathEdgeIDs ?? [])).compactMap { $0 }
                    }
                }
            )
        ).sorted()
    }

    private func combinedEvidenceTiers(for group: RepeatedTraceSegment) -> [KnowledgeTier] {
        Array(Set(group.segments.flatMap(\.evidenceTiers))).sorted { $0.rawValue < $1.rawValue }
    }

    private func stablePlanningStateID(
        for group: RepeatedTraceSegment,
        stepIndex: Int
    ) -> String? {
        let stateIDs = orderedUnique(
            group.segments.compactMap { segment in
                guard segment.events.indices.contains(stepIndex) else { return nil }
                return segment.events[stepIndex].planningStateID
            }
        )
        guard stateIDs.count == 1 else {
            return nil
        }
        return stateIDs.first ?? nil
    }

    private func latestTimestamp(for group: RepeatedTraceSegment) -> Date? {
        group.segments.flatMap(\.events).map(\.timestamp).max()
    }

    private func taskPhase(for event: TraceEvent) -> TaskStepPhase {
        switch event.plannerFamily {
        case PlannerFamily.code.rawValue:
            return .engineering
        case PlannerFamily.mixed.rawValue:
            return .handoff
        default:
            return .operatingSystem
        }
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
