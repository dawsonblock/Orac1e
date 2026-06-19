import Foundation

public final class TraceRecorder {
    public let sessionID: String

    private var nextStepID: Int = 1
    private var events: [TraceEvent] = []

    public init(sessionID: String = UUID().uuidString) {
        self.sessionID = sessionID
    }

    public func makeStepID() -> Int {
        defer { nextStepID += 1 }
        return nextStepID
    }

    public func record(_ event: TraceEvent) {
        events.append(event)
    }

    public func allEvents() -> [TraceEvent] {
        events
    }

    public func reset() {
        events.removeAll()
        nextStepID = 1
    }
}
