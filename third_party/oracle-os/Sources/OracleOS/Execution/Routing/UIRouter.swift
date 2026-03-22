import AppKit
import Foundation

public struct UIRouter: @unchecked Sendable {
    private let automationHost: AutomationHost?

    init(automationHost: AutomationHost?) {
        self.automationHost = automationHost
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> RoutedExecutionResult {
        guard command.type == .ui else {
            throw RouterError.invalidRoute(expected: .ui, actual: command.type)
        }

        #if DEBUG
        if let automationHost = automationHost {
            NSLog("UIRouter executing with automation host: \(automationHost)")
        }
        #endif

        guard case .ui(let action) = command.payload else {
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid UI payload",
                policyDecision: policyDecision,
                router: "ui"
            )
        }

        let result = await MainActor.run { execute(action) }
        let observations = [
            ObservationPayload.uiAction(
                action: action.name,
                target: action.query ?? action.domID ?? action.app ?? action.windowTitle,
                result: result.summary
            ),
        ]

        if result.success {
            return CommandRouter.successOutcome(
                command: command,
                observations: observations,
                artifacts: [],
                policyDecision: policyDecision,
                router: "ui",
                emittedEvents: successEvents(for: command, action: action, result: result),
                expectedPostconditions: expectedPostconditions(for: action, result: result)
            )
        }

        return CommandRouter.failureOutcome(
            command: command,
            reason: result.error ?? result.summary,
            policyDecision: policyDecision,
            router: "ui"
        )
    }

    private func successEvents(for command: Command, action: UIAction, result: ToolResult) -> [EventEnvelope] {
        var events: [EventEnvelope] = []
        let observedApp = result.context?.app ?? action.app
        let observedWindow = result.context?.window ?? action.windowTitle
        let observedURL = result.context?.url ?? action.query.flatMap { raw in
            URL(string: raw) != nil ? raw : nil
        }

        if let observedApp {
            events.append(
                CommandRouter.makeEvent(
                    command: command,
                    eventType: EventKinds.appFocused,
                    payload: AppFocusedPayload(appName: observedApp)
                )
            )
        }

        if observedApp != nil || observedWindow != nil {
            events.append(
                CommandRouter.makeEvent(
                    command: command,
                    eventType: EventKinds.windowFocused,
                    payload: WindowFocusedPayload(appName: observedApp, windowTitle: observedWindow)
                )
            )
        }

        if let observedURL {
            events.append(
                CommandRouter.makeEvent(
                    command: command,
                    eventType: EventKinds.navigationObserved,
                    payload: NavigationObservedPayload(url: observedURL, appName: observedApp)
                )
            )
        }

        if let observationPayload = makeObservationPayload(result: result, fallbackApp: observedApp, fallbackWindow: observedWindow, fallbackURL: observedURL) {
            events.append(
                CommandRouter.makeEvent(
                    command: command,
                    eventType: EventKinds.uiObservationCaptured,
                    payload: observationPayload
                )
            )
        }

        switch normalizedActionName(action.name) {
        case .click:
            events.append(
                CommandRouter.makeEvent(
                    command: command,
                    eventType: EventKinds.elementClicked,
                    payload: ElementClickedPayload(
                        appName: observedApp,
                        query: action.query,
                        domID: action.domID,
                        button: action.button
                    )
                )
            )

        case .type:
            events.append(
                CommandRouter.makeEvent(
                    command: command,
                    eventType: EventKinds.textEntered,
                    payload: TextEnteredPayload(
                        appName: observedApp,
                        query: action.query,
                        domID: action.domID,
                        textLength: action.text?.count ?? 0
                    )
                )
            )

        case .focus:
            break
        }

        return events
    }

    private func expectedPostconditions(for action: UIAction, result: ToolResult) -> [ExpectedPostcondition] {
        var expectations: [ExpectedPostcondition] = []
        let observedApp = result.context?.app ?? action.app
        let observedWindow = result.context?.window ?? action.windowTitle
        let observedURL = result.context?.url ?? action.query.flatMap { raw in
            URL(string: raw) != nil ? raw : nil
        }

        switch normalizedActionName(action.name) {
        case .focus:
            if let observedApp { expectations.append(.activeApplication(observedApp)) }
            if let observedWindow { expectations.append(.windowTitleContains(observedWindow)) }
            if let observedURL { expectations.append(.urlContains(observedURL)) }
        case .click, .type:
            if let observedApp { expectations.append(.activeApplication(observedApp)) }
            if let observedWindow, action.windowTitle != nil { expectations.append(.windowTitleContains(observedWindow)) }
        }

        return expectations
    }

    private func makeObservationPayload(
        result: ToolResult,
        fallbackApp: String?,
        fallbackWindow: String?,
        fallbackURL: String?
    ) -> UIObservationEventPayload? {
        let visibleElementCount = intValue(forKeys: ["visibleElementCount", "elementCount"], in: result.data)
        let modalPresent = boolValue(forKeys: ["modalPresent", "isModal"], in: result.data)
        let observationHash = stringValue(forKeys: ["observationHash", "snapshotHash"], in: result.data)
        let appName = result.context?.app ?? fallbackApp
        let windowTitle = result.context?.window ?? fallbackWindow
        let url = result.context?.url ?? fallbackURL

        guard appName != nil || windowTitle != nil || url != nil || visibleElementCount != nil || modalPresent != nil || observationHash != nil else {
            return nil
        }

        return UIObservationEventPayload(
            appName: appName,
            windowTitle: windowTitle,
            url: url,
            visibleElementCount: visibleElementCount,
            modalPresent: modalPresent,
            observationHash: observationHash
        )
    }

    private func stringValue(forKeys keys: [String], in dictionary: [String: Any]?) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func intValue(forKeys keys: [String], in dictionary: [String: Any]?) -> Int? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
            if let value = dictionary[key] as? String, let parsed = Int(value) {
                return parsed
            }
        }
        return nil
    }

    private func boolValue(forKeys keys: [String], in dictionary: [String: Any]?) -> Bool? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.boolValue
            }
            if let value = dictionary[key] as? String {
                switch value.lowercased() {
                case "true", "1", "yes": return true
                case "false", "0", "no": return false
                default: break
                }
            }
        }
        return nil
    }

    private func normalizedActionName(_ name: String) -> NormalizedUIAction {
        switch name {
        case "click", "clickElement":
            return .click
        case "type", "typeText":
            return .type
        default:
            return .focus
        }
    }

    @MainActor
    private func execute(_ action: UIAction) -> ToolResult {
        switch action.name {
        case "click", "clickElement":
            return Actions.performClick(
                query: action.query,
                role: action.role,
                domId: action.domID,
                appName: action.app,
                x: action.x,
                y: action.y,
                button: action.button,
                count: action.count
            )
        case "type", "typeText":
            return Actions.performTypeText(
                text: action.text ?? "",
                into: action.query,
                domId: action.domID,
                appName: action.app,
                clear: action.clear ?? false
            )
        case "focus", "focusWindow", "launchApp":
            return Actions.performFocusApp(appName: action.app ?? "unknown", windowTitle: action.windowTitle)
        case "press":
            let modifiers = action.modifiers ?? action.role?.split(separator: "+").map(String.init)
            return Actions.performPressKey(key: action.query ?? "", modifiers: modifiers, appName: action.app)
        case "hotkey":
            let keys = action.modifiers
                ?? action.query?.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
                ?? []
            return Actions.performHotkey(keys: keys, appName: action.app)
        case "scroll", "scrollElement":
            return Actions.performScroll(
                direction: action.query ?? "down",
                amount: action.amount ?? action.count,
                appName: action.app,
                x: action.x,
                y: action.y
            )
        case "openURL":
            guard let rawURL = action.query, let url = URL(string: rawURL) else {
                return ToolResult(success: false, error: "Invalid URL: \(action.query ?? "nil")")
            }
            let opened = NSWorkspace.shared.open(url)
            return ToolResult(
                success: opened,
                data: opened ? ["url": rawURL] : nil,
                error: opened ? nil : "Failed to open URL '\(rawURL)'"
            )
        case "window", "manageWindow":
            return Actions.performWindowAction(
                action: action.query ?? "list",
                appName: action.app ?? "unknown",
                windowTitle: action.windowTitle,
                x: action.x,
                y: action.y,
                width: action.width,
                height: action.height
            )
        case "read", "readElement":
            return AXScanner.readContent(appName: action.app, query: action.query, depth: nil)
        default:
            return ToolResult(success: false, error: "Unsupported UI action: \(action.name)")
        }
    }
}

private enum NormalizedUIAction {
    case click
    case type
    case focus
}

private extension ToolResult {
    var summary: String {
        if let summary = data?["summary"] as? String, !summary.isEmpty {
            return summary
        }
        if let error, !error.isEmpty {
            return error
        }
        return success ? "success" : "failed"
    }
}
