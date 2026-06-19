import Foundation

public struct ParameterizedAction: Sendable, Equatable {
    public let actionName: String
    public let originalTarget: String?
    public let parameterizedTarget: String?
    public let parameterSlots: [String]

    public init(
        actionName: String,
        originalTarget: String?,
        parameterizedTarget: String?,
        parameterSlots: [String] = []
    ) {
        self.actionName = actionName
        self.originalTarget = originalTarget
        self.parameterizedTarget = parameterizedTarget
        self.parameterSlots = parameterSlots
    }
}

public struct ParameterizedWorkflow: Sendable {
    public let goalPattern: String
    public let actions: [ParameterizedAction]
    public let parameterSlots: [String]
    public let parameterKinds: [String: String]

    public init(
        goalPattern: String,
        actions: [ParameterizedAction],
        parameterSlots: [String],
        parameterKinds: [String: String] = [:]
    ) {
        self.goalPattern = goalPattern
        self.actions = actions
        self.parameterSlots = parameterSlots
        self.parameterKinds = parameterKinds
    }
}

public struct WorkflowParameterizer: Sendable {

    public init() {}

    public func parameterize(
        goalPattern: String,
        traces: [[TraceEvent]]
    ) -> ParameterizedWorkflow? {
        guard traces.count >= 2,
              let representative = traces.first,
              !representative.isEmpty
        else {
            return nil
        }

        let extractedParameters = ParameterExtractor.extract(
            from: traces.map { events in
                TraceSegment(
                    id: UUID().uuidString,
                    taskID: nil,
                    sessionID: "parameterizer",
                    agentKind: AgentKind(rawValue: events.first?.agentKind ?? "os") ?? .os,
                    events: events
                )
            }
        )

        let actions = representative.enumerated().map { index, event -> ParameterizedAction in
            let parameterizedTarget = ParameterExtractor.applySlots(
                to: event.actionTarget ?? event.selectedElementLabel,
                parameters: extractedParameters,
                stepIndex: index
            )
            let slots = extractedParameters
                .filter { $0.stepIndex == nil || $0.stepIndex == index }
                .map(\.name)

            return ParameterizedAction(
                actionName: event.actionName,
                originalTarget: event.actionTarget ?? event.selectedElementLabel,
                parameterizedTarget: parameterizedTarget,
                parameterSlots: slots
            )
        }

        let allSlots = Array(Set(extractedParameters.map { $0.name })).sorted()
        let kinds = Dictionary(extractedParameters.map { ($0.name, $0.kind) }, uniquingKeysWith: { first, _ in first })

        return ParameterizedWorkflow(
            goalPattern: goalPattern,
            actions: actions,
            parameterSlots: allSlots,
            parameterKinds: kinds
        )
    }
}
