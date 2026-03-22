import Foundation

public struct CommandRouter: @unchecked Sendable {
    private let systemRouter: SystemRouter
    private let uiRouter: UIRouter
    private let codeRouter: CodeRouter

    public init(
        automationHost: AutomationHost? = nil,
        workspaceRunner: WorkspaceRunner? = nil,
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer()
    ) {
        self.systemRouter = SystemRouter(workspaceRunner: workspaceRunner)
        self.uiRouter = UIRouter(automationHost: automationHost)
        self.codeRouter = CodeRouter(
            workspaceRunner: workspaceRunner,
            repositoryIndexer: repositoryIndexer
        )
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> RoutedExecutionResult {
        switch command.type {
        case .system:
            return try await systemRouter.execute(command, policyDecision: policyDecision)
        case .ui:
            return try await uiRouter.execute(command, policyDecision: policyDecision)
        case .code:
            return try await codeRouter.execute(command, policyDecision: policyDecision)
        }
    }

    public static func domain(for command: Command) -> CommandType {
        command.type
    }

    static func successOutcome(
        command: Command,
        observations: [ObservationPayload],
        artifacts: [ArtifactPayload],
        policyDecision: PolicyDecision,
        router: String,
        emittedEvents: [EventEnvelope] = [],
        expectedPostconditions: [ExpectedPostcondition] = []
    ) -> RoutedExecutionResult {
        let notes = ["router=\(router)"]
        let evidence = ExecutionEvidence(
            observations: observations,
            artifacts: artifacts,
            events: emittedEvents,
            expectedPostconditions: expectedPostconditions,
            notes: notes
        )
        return RoutedExecutionResult(status: .success, evidence: evidence)
    }

    static func failureOutcome(
        command: Command,
        reason: String,
        policyDecision: PolicyDecision,
        router: String,
        status: ExecutionStatus = .failed,
        emittedEvents: [EventEnvelope] = []
    ) -> RoutedExecutionResult {
        let evidence = ExecutionEvidence(
            observations: [],
            artifacts: [],
            events: emittedEvents,
            expectedPostconditions: [],
            notes: ["router=\(router)", reason]
        )
        return RoutedExecutionResult(status: status, evidence: evidence)
    }

    static func makeEvent<P: Encodable>(
        command: Command,
        eventType: String,
        payload: P
    ) -> EventEnvelope {
        let encoder = OracleJSONCoding.makeEncoder()
        let encodedPayload = (try? encoder.encode(payload)) ?? Data()
        return EventEnvelope(
            sequenceNumber: 0,
            commandID: command.id,
            intentID: command.metadata.intentID,
            timestamp: Date(),
            eventType: eventType,
            payload: encodedPayload
        )
    }
}
