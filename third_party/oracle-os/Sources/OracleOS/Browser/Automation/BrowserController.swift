import Foundation

@MainActor
public final class BrowserController {
    public init() {}

    public func snapshot(appName: String?, observation: Observation) -> PageSnapshot? {
        guard isBrowserApp(observation.app ?? appName) else { return nil }
        let elements = DOMFlattener.flatten(DOMScanner.listInteractiveElements() ?? [])
        let text = PageTextReducer.reduce(
            title: observation.windowTitle,
            url: observation.url,
            elements: elements
        )
        let domain = observation.url.flatMap { URL(string: $0)?.host }

        return PageSnapshot(
            browserApp: observation.app ?? appName ?? "Browser",
            title: observation.windowTitle,
            url: observation.url,
            domain: domain,
            simplifiedText: text,
            indexedElements: elements
        )
    }

    public func isBrowserApp(_ appName: String?) -> Bool {
        guard let appName else { return false }
        let normalized = appName.lowercased()
        return normalized.contains("chrome")
            || normalized.contains("safari")
            || normalized.contains("firefox")
            || normalized.contains("arc")
    }
}
