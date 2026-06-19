import Foundation

public struct RuntimeStateReducer: EventReducer {
    public init() {}

    public func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        let snapshot = state.snapshot
        var cycleCount = snapshot.cycleCount
        var processNames = snapshot.processNames
        var notes = snapshot.notes

        for event in events {
            let lifecyclePayload = EventPayloadDecoder.decode(CommandLifecyclePayload.self, from: event)
            let payload = ReducerSupport.dictionary(from: event)

            switch event.eventType {
            case EventKinds.commandSucceeded, EventKinds.commandFailed:
                cycleCount += 1

            case EventKinds.policyRejected:
                let reason = lifecyclePayload?.reason
                    ?? ReducerSupport.string("reason", in: payload)
                    ?? "policy rejected"
                notes = ReducerSupport.appendUnique(notes, value: reason, limit: 20)

            default:
                break
            }

            if let names = lifecyclePayload?.processNames ?? ReducerSupport.stringArray("processNames", in: payload) {
                processNames = ReducerSupport.unique(names)
            }

            if event.eventType == EventKinds.commandFailed {
                let router = lifecyclePayload?.router ?? ReducerSupport.string("router", in: payload)
                notes = ReducerSupport.appendUnique(notes, value: router.map { "command failed via \($0)" }, limit: 20)
            }
        }

        state.replaceCommittedSnapshot(
            snapshot.copy(
                processNames: processNames,
                notes: notes,
                cycleCount: cycleCount
            )
        )
    }
}
