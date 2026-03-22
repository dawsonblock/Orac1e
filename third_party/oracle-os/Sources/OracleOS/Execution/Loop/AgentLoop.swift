import Foundation

@MainActor
public final class AgentLoop {
    let intake: any IntentSource
    let orchestrator: any IntentAPI
    var running = true

    public init(
        intake: any IntentSource,
        orchestrator: any IntentAPI
    ) {
        self.intake = intake
        self.orchestrator = orchestrator
    }

    public func stop() {
        running = false
    }
}
