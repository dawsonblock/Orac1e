import Foundation

/// The return type of VerifiedExecutor.
/// INVARIANT: Executor returns events and artifacts ONLY — no committed state writes.
public struct ExecutionOutcome: Sendable {
    public let commandID: CommandID
    public let status: ExecutionStatus
    public let events: [EventEnvelope]
    public let verifierReport: VerifierReport
    public let observations: [ObservationPayload]
    public let artifacts: [ArtifactPayload]
    public let evidence: ExecutionEvidence

    public init(
        commandID: CommandID,
        status: ExecutionStatus,
        observations: [ObservationPayload] = [],
        artifacts: [ArtifactPayload] = [],
        events: [EventEnvelope],
        verifierReport: VerifierReport,
        evidence: ExecutionEvidence? = nil
    ) {
        self.commandID = commandID
        self.status = status
        self.observations = observations
        self.artifacts = artifacts
        self.verifierReport = verifierReport

        let resolvedEvents: [EventEnvelope]
        if events.isEmpty {
            let fallbackEventType: String = (status == .success) ? EventKinds.commandSucceeded : EventKinds.commandFailed
            let payload = (try? OracleJSONCoding.makeEncoder().encode(CommandLifecyclePayload(status: status.rawValue))) ?? Data()
            resolvedEvents = [
                EventEnvelope(
                    sequenceNumber: 0,
                    commandID: commandID,
                    intentID: nil,
                    timestamp: Date(),
                    eventType: fallbackEventType,
                    payload: payload
                ),
            ]
        } else {
            resolvedEvents = events
        }
        self.events = resolvedEvents
        self.evidence = evidence ?? ExecutionEvidence(
            observations: observations,
            artifacts: artifacts,
            events: resolvedEvents
        )
    }

    public static func failure(from error: any Error, command: Command) -> ExecutionOutcome {
        let reason = error.localizedDescription
        let payload = (try? OracleJSONCoding.makeEncoder().encode(CommandLifecyclePayload(status: ExecutionStatus.failed.rawValue, reason: reason))) ?? Data()
        let events = [
            EventEnvelope(
                sequenceNumber: 0,
                commandID: command.id,
                intentID: command.metadata.intentID,
                timestamp: Date(),
                eventType: EventKinds.commandStarted,
                payload: (try? OracleJSONCoding.makeEncoder().encode(CommandLifecyclePayload(status: "started"))) ?? Data()
            ),
            EventEnvelope(
                sequenceNumber: 0,
                commandID: command.id,
                intentID: command.metadata.intentID,
                timestamp: Date(),
                eventType: EventKinds.commandFailed,
                payload: payload
            ),
        ]
        return ExecutionOutcome(
            commandID: command.id,
            status: .failed,
            observations: [],
            artifacts: [],
            events: events,
            verifierReport: VerifierReport(
                commandID: command.id,
                preconditionsPassed: false,
                policyDecision: "error",
                postconditionsPassed: false,
                notes: [reason]
            ),
            evidence: ExecutionEvidence(notes: [reason]).withEvents(events)
        )
    }
}

public enum ExecutionStatus: String, Sendable, Codable {
    case success, failed, partialSuccess, preconditionFailed, policyBlocked, postconditionFailed
}

public struct VerifierReport: Sendable, Codable {
    public let commandID: CommandID
    public let preconditionsPassed: Bool
    public let policyDecision: String
    public let postconditionsPassed: Bool
    public let notes: [String]
    public let timestamp: Date

    public init(commandID: CommandID, preconditionsPassed: Bool, policyDecision: String,
                postconditionsPassed: Bool, notes: [String] = [], timestamp: Date = Date()) {
        self.commandID = commandID; self.preconditionsPassed = preconditionsPassed
        self.policyDecision = policyDecision; self.postconditionsPassed = postconditionsPassed
        self.notes = notes; self.timestamp = timestamp
    }
}

public struct ObservationPayload: Sendable, Codable {
    public let kind: String; public let content: String; public let timestamp: Date
    public init(kind: String, content: String, timestamp: Date = Date()) {
        self.kind = kind; self.content = content; self.timestamp = timestamp }
}

public struct UIActionObservationPayload: Sendable, Codable {
    public let action: String
    public let target: String?
    public let result: String

    public init(action: String, target: String?, result: String) {
        self.action = action
        self.target = target
        self.result = result
    }
}

public extension ObservationPayload {
    static func uiAction(action: String, target: String?, result: String) -> ObservationPayload {
        let payload = UIActionObservationPayload(action: action, target: target, result: result)
        let content: String
        if let data = try? JSONEncoder().encode(payload),
           let encoded = String(data: data, encoding: .utf8)
        {
            content = encoded
        } else {
            content = result
        }
        return ObservationPayload(kind: "ui.action", content: content)
    }
}

public struct ArtifactPayload: Sendable, Codable {
    public let kind: String; public let identifier: String; public let data: Data?
    public init(kind: String, identifier: String, data: Data? = nil) {
        self.kind = kind; self.identifier = identifier; self.data = data }
}

/// Result of the critic evaluation phase in RuntimeOrchestrator.
/// Classifies the execution outcome and signals whether recovery is needed.
public struct EvaluationResult: Sendable {
    public let commandID: CommandID
    public let criticOutcome: CriticOutcome
    public let needsRecovery: Bool
    public let notes: [String]

    public init(commandID: CommandID, criticOutcome: CriticOutcome, needsRecovery: Bool, notes: [String] = []) {
        self.commandID = commandID; self.criticOutcome = criticOutcome
        self.needsRecovery = needsRecovery; self.notes = notes
    }
}
