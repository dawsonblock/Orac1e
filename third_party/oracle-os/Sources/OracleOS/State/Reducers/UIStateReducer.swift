import Foundation

public struct UIStateReducer: EventReducer {
    public init() {}

    public func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        let snapshot = state.snapshot
        var activeApplication = snapshot.activeApplication
        var windowTitle = snapshot.windowTitle
        var url = snapshot.url
        var visibleElementCount = snapshot.visibleElementCount
        var modalPresent = snapshot.modalPresent
        var observationHash = snapshot.observationHash

        for event in events {
            let payload = ReducerSupport.dictionary(from: event)

            switch event.eventType {
            case EventKinds.uiObservationCaptured:
                let typed = EventPayloadDecoder.decode(UIObservationEventPayload.self, from: event)
                if let value = typed?.appName ?? ReducerSupport.string("appName", in: payload) ?? ReducerSupport.string("app", in: payload) {
                    activeApplication = value
                }
                if let value = typed?.windowTitle ?? ReducerSupport.string("windowTitle", in: payload) {
                    windowTitle = value
                }
                if let value = typed?.url ?? ReducerSupport.string("url", in: payload) {
                    url = value
                }
                if let value = typed?.visibleElementCount ?? ReducerSupport.int("visibleElementCount", in: payload) {
                    visibleElementCount = value
                }
                if let value = typed?.modalPresent ?? ReducerSupport.bool("modalPresent", in: payload) {
                    modalPresent = value
                }
                if let value = typed?.observationHash ?? ReducerSupport.string("observationHash", in: payload) {
                    observationHash = value
                }

            case EventKinds.appFocused:
                let typed = EventPayloadDecoder.decode(AppFocusedPayload.self, from: event)
                activeApplication = typed?.appName
                    ?? ReducerSupport.string("appName", in: payload)
                    ?? ReducerSupport.string("app", in: payload)
                    ?? activeApplication

            case EventKinds.windowFocused:
                let typed = EventPayloadDecoder.decode(WindowFocusedPayload.self, from: event)
                if let value = typed?.appName ?? ReducerSupport.string("appName", in: payload) ?? ReducerSupport.string("app", in: payload) {
                    activeApplication = value
                }
                if let value = typed?.windowTitle ?? ReducerSupport.string("windowTitle", in: payload) {
                    windowTitle = value
                }

            case EventKinds.navigationObserved:
                let typed = EventPayloadDecoder.decode(NavigationObservedPayload.self, from: event)
                if let value = typed?.url ?? ReducerSupport.string("url", in: payload) {
                    url = value
                }
                if let value = typed?.appName ?? ReducerSupport.string("appName", in: payload) ?? ReducerSupport.string("app", in: payload) {
                    activeApplication = value
                }

            default:
                break
            }
        }

        state.replaceCommittedSnapshot(
            snapshot.copy(
                activeApplication: .some(activeApplication),
                windowTitle: .some(windowTitle),
                url: .some(url),
                visibleElementCount: visibleElementCount,
                modalPresent: modalPresent,
                observationHash: .some(observationHash)
            )
        )
    }
}
