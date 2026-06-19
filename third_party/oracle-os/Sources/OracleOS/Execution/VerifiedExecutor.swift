import Foundation

/// The ONLY layer allowed to produce side effects in Oracle-OS.
///
/// INVARIANTS:
///   - Executor observes and acts, but does NOT commit state
///   - Executor returns ExecutionOutcome with events and artifacts only
///   - CommitCoordinator is the ONLY entity that writes committed state
public actor VerifiedExecutor {
    private let policyEngine: PolicyEngine
    private let commandRouter: CommandRouter
    private let preconditionsValidator: PreconditionsValidator
    private let postconditionsValidator: PostconditionsValidator
    private let postExecutionObserver: PostExecutionObserver
    private let outcomeVerifier: OutcomeVerifier
    private let snapshotProvider: @Sendable () async -> WorldModelSnapshot

    public init(
        policyEngine: PolicyEngine = .shared,
        commandRouter: CommandRouter = CommandRouter(),
        preconditionsValidator: PreconditionsValidator = PreconditionsValidator(),
        postconditionsValidator: PostconditionsValidator = PostconditionsValidator(),
        postExecutionObserver: PostExecutionObserver = PostExecutionObserver(),
        outcomeVerifier: OutcomeVerifier = OutcomeVerifier(),
        snapshotProvider: @escaping @Sendable () async -> WorldModelSnapshot
    ) {
        self.policyEngine = policyEngine
        self.commandRouter = commandRouter
        self.preconditionsValidator = preconditionsValidator
        self.postconditionsValidator = postconditionsValidator
        self.postExecutionObserver = postExecutionObserver
        self.outcomeVerifier = outcomeVerifier
        self.snapshotProvider = snapshotProvider
    }

    /// Execute a validated command and return outcome with events.
    /// IMPORTANT: This does NOT commit state — only returns events for CommitCoordinator.
    public func execute(_ command: Command) async throws -> ExecutionOutcome {
        let started = makeEvent(
            command: command,
            eventType: EventKinds.commandStarted,
            payload: CommandLifecyclePayload(status: "started")
        )

        let snapshot = await snapshotProvider()
        do {
            try preconditionsValidator.validate(command, snapshot: snapshot)
        } catch {
            return failOutcome(
                command: command,
                status: .preconditionFailed,
                reason: error.localizedDescription,
                preconditionsPassed: false,
                policyDecision: "not_evaluated",
                postconditionsPassed: false,
                extraEvents: [started]
            )
        }

        let policyDecision = try policyEngine.validate(command)
        guard policyDecision.allowed else {
            return failOutcome(
                command: command,
                status: .policyBlocked,
                reason: policyDecision.reason ?? "Policy rejected",
                preconditionsPassed: true,
                policyDecision: "blocked",
                postconditionsPassed: false,
                extraEvents: [
                    started,
                    makeEvent(
                        command: command,
                        eventType: EventKinds.policyRejected,
                        payload: CommandLifecyclePayload(status: "blocked", reason: policyDecision.reason ?? "blocked")
                    ),
                ]
            )
        }

        do {
            let routed = try await commandRouter.execute(command, policyDecision: policyDecision)
            let observed = await postExecutionObserver.observe(
                command: command,
                evidence: routed.evidence,
                snapshotBeforeExecution: snapshot
            )
            let report = outcomeVerifier.verify(
                command: command,
                snapshotBeforeExecution: snapshot,
                routedResult: routed,
                observedAfterExecution: observed,
                policyDecision: policyDecision,
                preconditionsPassed: true
            )

            let finalStatus: ExecutionStatus
            if routed.status == .success && report.postconditionsPassed {
                finalStatus = .success
            } else if routed.status == .success {
                finalStatus = .postconditionFailed
            } else {
                finalStatus = routed.status
            }

            let terminalEventType = finalStatus == .success ? EventKinds.commandSucceeded : EventKinds.commandFailed
            let terminalReason = report.notes.joined(separator: "; ")
            let terminalEvent = makeEvent(
                command: command,
                eventType: terminalEventType,
                payload: CommandLifecyclePayload(
                    status: finalStatus.rawValue,
                    reason: terminalReason.isEmpty ? nil : terminalReason
                )
            )
            let allEvents = [started] + routed.evidence.events + [terminalEvent]
            let evidence = routed.evidence.withEvents(allEvents)
            let outcome = ExecutionOutcome(
                commandID: command.id,
                status: finalStatus,
                observations: evidence.observations,
                artifacts: evidence.artifacts,
                events: allEvents,
                verifierReport: report,
                evidence: evidence
            )

            _ = try postconditionsValidator.validate(command, outcome: outcome)
            return outcome
        } catch {
            return failOutcome(
                command: command,
                status: .failed,
                reason: error.localizedDescription,
                preconditionsPassed: true,
                policyDecision: "approved",
                postconditionsPassed: false,
                extraEvents: [started]
            )
        }
    }

    private func failOutcome(
        command: Command,
        status: ExecutionStatus,
        reason: String,
        preconditionsPassed: Bool,
        policyDecision: String,
        postconditionsPassed: Bool,
        extraEvents: [EventEnvelope] = []
    ) -> ExecutionOutcome {
        let report = VerifierReport(
            commandID: command.id,
            preconditionsPassed: preconditionsPassed,
            policyDecision: policyDecision,
            postconditionsPassed: postconditionsPassed,
            notes: [reason]
        )
        var events = extraEvents
        events.append(
            makeEvent(
                command: command,
                eventType: EventKinds.commandFailed,
                payload: CommandLifecyclePayload(status: status.rawValue, reason: reason)
            )
        )
        let evidence = ExecutionEvidence(notes: [reason]).withEvents(events)
        return ExecutionOutcome(
            commandID: command.id,
            status: status,
            observations: [],
            artifacts: [],
            events: events,
            verifierReport: report,
            evidence: evidence
        )
    }

    private func makeEvent<P: Encodable>(
        command: Command,
        eventType: String,
        payload: P
    ) -> EventEnvelope {
        let encodedPayload = (try? OracleJSONCoding.makeEncoder().encode(payload)) ?? Data()
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
