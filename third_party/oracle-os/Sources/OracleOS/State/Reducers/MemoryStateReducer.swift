import Foundation

public struct MemoryStateReducer: EventReducer {
    public init() {}

    public func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        let snapshot = state.snapshot
        var knowledgeSignals = snapshot.knowledgeSignals
        var notes = snapshot.notes

        for event in events {
            let payload = ReducerSupport.dictionary(from: event)

            switch event.eventType {
            case EventKinds.lessonPromoted:
                let signal = EventPayloadDecoder.decode(LessonPromotedPayload.self, from: event)?.signal
                    ?? ReducerSupport.string("signal", in: payload)
                    ?? ReducerSupport.string("lesson", in: payload)
                knowledgeSignals = ReducerSupport.appendUnique(knowledgeSignals, value: signal)

            case EventKinds.recipeRecorded:
                let name = EventPayloadDecoder.decode(RecipeRecordedPayload.self, from: event)?.name
                    ?? ReducerSupport.string("name", in: payload)
                    ?? "recipe recorded"
                notes = ReducerSupport.appendUnique(notes, value: name, limit: 20)

            case EventKinds.traceSaved:
                let trace = EventPayloadDecoder.decode(TraceSavedPayload.self, from: event)?.traceID
                    ?? ReducerSupport.string("traceID", in: payload)
                    ?? "trace saved"
                notes = ReducerSupport.appendUnique(notes, value: trace, limit: 20)

            default:
                break
            }
        }

        state.replaceCommittedSnapshot(
            snapshot.copy(
                knowledgeSignals: knowledgeSignals,
                notes: notes
            )
        )
    }
}
