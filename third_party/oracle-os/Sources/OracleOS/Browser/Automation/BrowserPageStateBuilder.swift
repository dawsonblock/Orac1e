import Foundation

@MainActor
public final class BrowserPageStateBuilder {
    private let controller: BrowserController

    public init(controller: BrowserController = BrowserController()) {
        self.controller = controller
    }

    public func build(from observation: Observation) -> BrowserSession? {
        guard controller.isBrowserApp(observation.app) else { return nil }
        let snapshot = controller.snapshot(appName: observation.app, observation: observation)
        return BrowserSession(
            appName: observation.app ?? "Browser",
            page: snapshot,
            available: snapshot != nil
        )
    }
}
