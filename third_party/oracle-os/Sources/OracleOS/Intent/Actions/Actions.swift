// Actions.swift - All action functions for Oracle OS v2
//
// Maps to MCP tools: oracle_click, oracle_type, oracle_press, oracle_hotkey,
// oracle_scroll, oracle_window
//
// Architecture: Uses AXorcist's COMMAND SYSTEM (runCommand with Locators)
// for AX-native operations, with synthetic fallback for Chrome/web apps.
//
// The Action Loop (every action follows this):
// 1. PRE-FLIGHT: find element via AXorcist, check actionable
// 2. EXECUTE: AX-native first, synthetic fallback if no state change
// 3. POST-VERIFY: brief pause, read post-action context
// 4. CLEANUP: clear modifier flags, restore focus

import AppKit
import AXorcist
import Foundation

/// Errors that can occur during action execution
public enum ActionError: Error, Sendable {
    case invalidParameter(String)
    case elementNotFound(String)
    case actionFailed(String)
}

// MARK: - Safe Parameter Extraction

/// Safely extract a String parameter, returning nil if not present or wrong type
private func extractString(_ params: [String: Any], _ key: String) -> String? {
    params[key] as? String
}

/// Safely extract an Int parameter, returning nil if not present or wrong type
private func extractInt(_ params: [String: Any], _ key: String) -> Int? {
    if let i = params[key] as? Int { return i }
    if let d = params[key] as? Double { return Int(d) }
    if let s = params[key] as? String, let i = Int(s) { return i }
    return nil
}

/// Safely extract a Double parameter, returning nil if not present or wrong type
private func extractDouble(_ params: [String: Any], _ key: String) -> Double? {
    if let d = params[key] as? Double { return d }
    if let i = params[key] as? Int { return Double(i) }
    if let s = params[key] as? String, let d = Double(s) { return d }
    return nil
}

/// Safely extract a Bool parameter, returning nil if not present or wrong type
private func extractBool(_ params: [String: Any], _ key: String) -> Bool? {
    params[key] as? Bool
}

/// Actions module: operating apps for the agent.
/// 
/// Note: This module uses `Thread.sleep(forTimeInterval:)` for timing-critical UI waits.
/// These are intentionally kept short (50-300ms) to balance responsiveness with reliability.
/// In a @MainActor context, these block the thread, but they are necessary for waiting
/// for UI state changes to propagate. Future refactoring could explore async alternatives
/// if the Swift concurrency story for UI automation matures.
@MainActor
public enum Actions {
    private static func plannerFamily(for agentKind: AgentKind) -> PlannerFamily {
        switch agentKind {
        case .os: .os
        case .code: .code
        case .mixed: .mixed
        }
    }

    private static func stepPhase(for agentKind: AgentKind) -> TaskStepPhase {
        switch agentKind {
        case .code: .engineering
        case .os, .mixed: .operatingSystem
        }
    }

    private static func executeThroughRuntime(
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface,
        actionIntent: @autoclosure () -> ActionIntent
    ) -> ToolResult {
        let intent = actionIntent()
        let family = plannerFamily(for: intent.agentKind)
        let actionContract = ActionContract.from(
            intent: intent,
            method: "intent-api-forwarder",
            selectedElementLabel: intent.targetQuery,
            plannerFamily: family.rawValue
        )
        let plannerDecision = PlannerDecision(
            agentKind: intent.agentKind,
            plannerFamily: family,
            stepPhase: stepPhase(for: intent.agentKind),
            actionContract: actionContract,
            source: .strategy,
            notes: ["actions.intent-api-forwarder", "surface=\(surface.rawValue)"]
        )
        let driver = RuntimeExecutionDriver(intentAPI: runtime, surface: surface)
        return driver.execute(
            intent: intent,
            plannerDecision: plannerDecision,
            selectedCandidate: nil
        )
    }

    // MARK: - oracle_click

    /// Click an element. AX-native first via AXorcist's PerformAction command,
    /// synthetic fallback with position-based click.
    public static func click(
        query: String?,
        role: String?,
        domId: String?,
        appName: String?,
        x: Double?,
        y: Double?,
        button: String?,
        count: Int?,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_click"
    ) -> ToolResult {
        _ = approvalRequestID
        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.click(
                app: appName,
                query: query,
                role: role,
                domID: domId,
                x: x,
                y: y,
                button: button,
                count: count,
                postconditions: inferredClickPostconditions(query: query, role: role, domId: domId)
            )
        )
    }

    static func performClick(
        query: String?,
        role: String?,
        domId: String?,
        appName: String?,
        x: Double?,
        y: Double?,
        button: String?,
        count: Int?
    ) -> ToolResult {
        let mouseButton: MouseButton = switch button {
        case "right": .right
        case "middle": .middle
        default: .left
        }
        let clickCount = max(1, count ?? 1)

        // Coordinate-based click (no element lookup)
        if let x, let y {
            if let appName {
                _ = FocusManager.focus(appName: appName)
                Thread.sleep(forTimeInterval: 0.2)
            }
            do {
                try InputDriver.click(at: CGPoint(x: x, y: y), button: mouseButton, count: clickCount)
                Thread.sleep(forTimeInterval: 0.15)
                return ToolResult(
                    success: true,
                    data: ["method": "coordinate", "x": x, "y": y]
                )
            } catch {
                return ToolResult(success: false, error: "Click at (\(Int(x)), \(Int(y))) failed: \(error)")
            }
        }

        // Element-based click needs query or domId
        guard query != nil || domId != nil else {
            return ToolResult(
                success: false,
                error: "Either query/dom_id or x/y coordinates required",
                suggestion: "Use oracle_find to locate elements, or oracle_element_at for coordinates"
            )
        }

        // Build locator for AXorcist
        let locator = LocatorBuilder.build(query: query, role: role, domId: domId)

        // Find element position, synthetic/native click fallback.
        // Need to find the element ourselves to get its position
        let element = findElement(locator: locator, appName: appName)

        // Strategy 2.5a: CDP fallback — try Chrome DevTools Protocol for web apps.
        // Much faster than VLM (~50ms vs 3s), but requires Chrome debug port.
        if element == nil, let query {
            if DOMScanner.isAvailable(),
               let cdpElements = DOMScanner.findElements(query: query),
               let firstMatch = cdpElements.first
            {
                let viewportX = firstMatch["centerX"] as? Int ?? 0
                let viewportY = firstMatch["centerY"] as? Int ?? 0

                // Get Chrome window origin for coordinate conversion
                let windowOrigin: (x: Double, y: Double)
                if let appName,
                   let app = AXScanner.findApp(named: appName),
                   let appElement = Element.application(for: app.processIdentifier),
                   let window = appElement.focusedWindow(),
                   let pos = window.position()
                {
                    windowOrigin = (Double(pos.x), Double(pos.y))
                } else {
                    windowOrigin = (0, 0)
                }

                let screenCoords = DOMScanner.viewportToScreen(
                    viewportX: Double(viewportX),
                    viewportY: Double(viewportY),
                    windowX: windowOrigin.x,
                    windowY: windowOrigin.y
                )

                if let appName {
                    _ = FocusManager.focus(appName: appName)
                    Thread.sleep(forTimeInterval: 0.2)
                }

                do {
                    try InputDriver.click(
                        at: CGPoint(x: screenCoords.x, y: screenCoords.y),
                        button: mouseButton,
                        count: clickCount
                    )
                    Thread.sleep(forTimeInterval: 0.15)
                    Log.info("CDP click: '\(query)' at (\(Int(screenCoords.x)), \(Int(screenCoords.y)))")
                    return ToolResult(
                        success: true,
                        data: [
                            "method": "cdp-grounded",
                            "element": query,
                            "x": screenCoords.x,
                            "y": screenCoords.y,
                            "match_type": firstMatch["matchType"] as? String ?? "unknown",
                        ]
                    )
                } catch {
                    Log.warn("CDP click failed: \(error)")
                }
            }
        }

        // Strategy 2.5b: Vision fallback — if AX AND CDP can't find it, try VLM grounding.
        // This handles web apps (Chrome AXGroup elements) and dynamic content.
        if element == nil, let query {
            if let visionResult = VisionScanner.visionFallbackClick(
                query: query,
                appName: appName
            ) {
                // VLM found the element — click at the grounded coordinates
                let vx = visionResult.data?["x"] as? Double ?? 0
                let vy = visionResult.data?["y"] as? Double ?? 0

                if let appName {
                    _ = FocusManager.focus(appName: appName)
                    Thread.sleep(forTimeInterval: 0.2)
                }

                do {
                    try InputDriver.click(
                        at: CGPoint(x: vx, y: vy),
                        button: mouseButton,
                        count: clickCount
                    )
                    Thread.sleep(forTimeInterval: 0.15)
                    return ToolResult(
                        success: true,
                        data: [
                            "method": "vlm-grounded",
                            "element": query,
                            "x": vx,
                            "y": vy,
                            "confidence": visionResult.data?["confidence"] as? Double ?? 0,
                            "inference_ms": visionResult.data?["inference_ms"] as? Int ?? 0,
                        ]
                    )
                } catch {
                    return ToolResult(
                        success: false,
                        error: "VLM-grounded click at (\(Int(vx)), \(Int(vy))) failed: \(error)"
                    )
                }
            }
        }

        guard let element else {
            return ToolResult(
                success: false,
                error: "Element '\(query ?? domId ?? "")' not found in \(appName ?? "frontmost app")",
                suggestion: "Use oracle_find to see what elements are available, or oracle_ground for visual search"
            )
        }

        // Pre-flight: check actionable
        if !element.isActionable() {
            return ToolResult(
                success: false,
                error: "Element '\(element.computedName() ?? query ?? "")' is not actionable",
                suggestion: "Element may be disabled, hidden, or off-screen. Use oracle_inspect to check."
            )
        }

        // Focus the app for synthetic input
        if let appName {
            _ = FocusManager.focus(appName: appName)
            Thread.sleep(forTimeInterval: 0.2)
        }

        do {
            try element.click(button: mouseButton, clickCount: clickCount)
            Thread.sleep(forTimeInterval: 0.15)
            return ToolResult(
                success: true,
                data: [
                    "method": "synthetic",
                    "element": element.computedName() ?? query ?? "",
                ]
            )
        } catch {
            return ToolResult(
                success: false,
                error: "Click failed: \(error)",
                suggestion: "Try oracle_inspect on the element, or use x/y coordinates"
            )
        }
    }

    // MARK: - oracle_type

    /// Type text into a field. Uses AXorcist's SetFocusedValue command for
    /// AX-native typing (focus + setValue), with synthetic typeText fallback.
    public static func typeText(
        text: String,
        into: String?,
        domId: String?,
        appName: String?,
        clear: Bool,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_type"
    ) -> ToolResult {
        _ = approvalRequestID
        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.type(
                app: appName,
                into: into,
                domID: domId,
                text: text,
                clear: clear,
                postconditions: inferredTypePostconditions(text: text, into: into, domId: domId)
            )
        )
    }

    static func performTypeText(
        text: String,
        into: String?,
        domId: String?,
        appName: String?,
        clear: Bool
    ) -> ToolResult {
        // If target field specified, find it and type into it
        if let fieldName = into ?? domId {
            // For 'into' parameter, use field-specific search that prefers
            // editable/interactive roles (AXComboBox, AXTextField, AXTextArea)
            // over random elements that happen to contain the text.
            // This prevents into:"To" from matching "Skip to content" instead
            // of the actual "To recipients" field.
            let element: Element?
            if let domId {
                let locator = LocatorBuilder.build(domId: domId)
                element = findElement(locator: locator, appName: appName)
            } else if let into {
                element = findEditableField(named: into, appName: appName)
            } else {
                element = nil
            }

            guard let element else {
                return ToolResult(
                    success: false,
                    error: "Field '\(fieldName)' not found",
                    suggestion: "Use oracle_find to see available fields, or oracle_context for orientation"
                )
            }

            // Strategy 1: AX-native setValue
            // Try setting value directly via AX API (works for native fields)
            if element.isAttributeSettable(named: "AXValue") {
                // Focus the element first
                _ = element.setValue(true, forAttribute: "AXFocused")
                Thread.sleep(forTimeInterval: 0.1)

                if clear {
                    _ = element.setValue("", forAttribute: "AXValue")
                    Thread.sleep(forTimeInterval: 0.05)
                }

                let setOk = element.setValue(text, forAttribute: "AXValue")
                if setOk {
                    usleep(150_000) // 150ms (v1's timing)

                    // Verify: read AXValue DIRECTLY via raw API on the SAME element.
                    // v1's proven pattern: raw AXUIElementCopyAttributeValue, not
                    // computedName/title fallbacks which return wrong data from
                    // stale handles or overlay elements.
                    var readBackRef: CFTypeRef?
                    let readBackOk = AXUIElementCopyAttributeValue(
                        element.underlyingElement,
                        "AXValue" as CFString,
                        &readBackRef
                    )
                    let readback: String?
                    if readBackOk == .success, let ref = readBackRef {
                        if let str = ref as? String, !str.isEmpty {
                            readback = str
                        } else if CFGetTypeID(ref) == CFStringGetTypeID() {
                            readback = (ref as! String)
                        } else {
                            readback = nil
                        }
                    } else {
                        readback = nil
                    }

                    // Check if first 10 chars match (v1's threshold)
                    let textPrefix = String(text.prefix(10))
                    if let readback, readback.contains(textPrefix) {
                        return ToolResult(
                            success: true,
                            data: [
                                "method": "ax-native-setValue",
                                "field": fieldName,
                                "typed": text,
                                "readback": String(readback.prefix(200)),
                            ]
                        )
                    }
                    Log.info("setValue for '\(fieldName)' readback doesn't match - falling back to click-then-type")
                }
            }

            // Strategy 2: Click the element to focus it, then type synthetically
            // This is what v1's ActionExecutor did and it works for Chrome/Gmail
            if let appName {
                _ = FocusManager.focus(appName: appName)
                Thread.sleep(forTimeInterval: 0.2)
            }

            // Click the element to put cursor in the field
            if element.isActionable() {
                do {
                    try element.click()
                    Thread.sleep(forTimeInterval: 0.15)
                } catch {
                    // Click failed, try AX focus as fallback
                    _ = element.setValue(true, forAttribute: "AXFocused")
                    Thread.sleep(forTimeInterval: 0.1)
                }
            } else {
                _ = element.setValue(true, forAttribute: "AXFocused")
                Thread.sleep(forTimeInterval: 0.1)
            }

            do {
                if clear {
                    try Element.performHotkey(keys: ["cmd", "a"])
                    Thread.sleep(forTimeInterval: 0.05)
                    try Element.typeKey(.delete)
                    Thread.sleep(forTimeInterval: 0.05)
                    FocusManager.clearModifierFlags()
                }
                try Element.typeText(text, delay: 0.01)
                Thread.sleep(forTimeInterval: 0.15)

                // Read back from the same element we found earlier
                let readback = readbackFromElement(element)
                let textPrefix = String(text.prefix(10))
                let verified = readback.contains(textPrefix)
                return ToolResult(
                    success: true,
                    data: [
                        "method": "click-then-type",
                        "field": fieldName,
                        "typed": text,
                        "verified": verified,
                        "readback": readback,
                    ]
                )
            } catch {
                return ToolResult(success: false, error: "Type into '\(fieldName)' failed: \(error)")
            }
        }

        // No target field - type at current focus
        if let appName {
            _ = FocusManager.focus(appName: appName)
            Thread.sleep(forTimeInterval: 0.2)
        }

        do {
            if clear {
                try Element.performHotkey(keys: ["cmd", "a"])
                Thread.sleep(forTimeInterval: 0.05)
                try Element.typeKey(.delete)
                Thread.sleep(forTimeInterval: 0.05)
                FocusManager.clearModifierFlags()
            }
            try Element.typeText(text, delay: 0.01)
            Thread.sleep(forTimeInterval: 0.1)
            return ToolResult(
                success: true,
                data: ["method": "synthetic-at-focus", "typed": text]
            )
        } catch {
            return ToolResult(success: false, error: "Type failed: \(error)")
        }
    }

    // MARK: - oracle_press

    /// Press a single key with optional modifiers.
    public static func pressKey(
        key: String,
        modifiers: [String]?,
        appName: String?,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_press"
    ) -> ToolResult {
        _ = approvalRequestID
        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.press(
                app: appName,
                key: key,
                modifiers: modifiers,
                postconditions: inferredPressPostconditions(appName: appName)
            )
        )
    }

    static func performPressKey(
        key: String,
        modifiers: [String]?,
        appName: String?
    ) -> ToolResult {
        if let appName {
            _ = FocusManager.focus(appName: appName)
            Thread.sleep(forTimeInterval: 0.2)
        }

        do {
            if let modifiers, !modifiers.isEmpty {
                // Key with modifiers = hotkey
                try Element.performHotkey(keys: modifiers + [key])
                FocusManager.clearModifierFlags()
                usleep(10_000) // 10ms for modifier clear to propagate
            } else if let specialKey = mapSpecialKey(key) {
                try Element.typeKey(specialKey)
            } else if key.count == 1 {
                try Element.typeText(key)
            } else {
                return ToolResult(
                    success: false,
                    error: "Unknown key: '\(key)'",
                    suggestion: "Valid: return, tab, escape, space, delete, up, down, left, right, f1-f12"
                )
            }
            return ToolResult(success: true, data: ["key": key])
        } catch {
            return ToolResult(success: false, error: "Key press failed: \(error)")
        }
    }

    public static func focusApp(
        appName: String,
        windowTitle: String? = nil,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_focus"
    ) -> ToolResult {
        _ = approvalRequestID
        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.focus(
                app: appName,
                windowTitle: windowTitle,
                postconditions: inferredFocusPostconditions(appName: appName, windowTitle: windowTitle)
            )
        )
    }

    static func performFocusApp(
        appName: String,
        windowTitle: String? = nil
    ) -> ToolResult {
        FocusManager.focus(appName: appName, windowTitle: windowTitle)
    }

    // MARK: - oracle_hotkey

    /// Press a key combination. Clears modifier flags after to prevent stuck keys.
    public static func hotkey(
        keys: [String],
        appName: String?,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_hotkey"
    ) -> ToolResult {
        guard !keys.isEmpty else {
            return ToolResult(success: false, error: "Keys array cannot be empty")
        }

        _ = approvalRequestID
        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.hotkey(
                app: appName,
                keys: keys,
                postconditions: inferredPressPostconditions(appName: appName)
            )
        )
    }

    static func performHotkey(
        keys: [String],
        appName: String?
    ) -> ToolResult {

        if let appName {
            _ = FocusManager.focus(appName: appName)
            Thread.sleep(forTimeInterval: 0.2)
        }

        do {
            try Element.performHotkey(keys: keys)
            // Clear modifier flags IMMEDIATELY after the key events.
            // v1's proven order: clear first, delay after.
            // If we delay before clearing, the system thinks Cmd is held for 200ms
            // which makes Chrome enter shortcut-hint mode (the "flicker") and
            // disrupts text selection in the address bar.
            FocusManager.clearModifierFlags()
            usleep(10_000) // 10ms for clear event to propagate
            usleep(200_000) // 200ms for app to process the hotkey result
            return ToolResult(success: true, data: ["keys": keys])
        } catch {
            FocusManager.clearModifierFlags()
            return ToolResult(success: false, error: "Hotkey \(keys.joined(separator: "+")) failed: \(error)")
        }
    }

    // MARK: - oracle_scroll

    /// Scroll in a direction. Uses AXorcist's element-based scroll when app is
    /// specified (auto-handles multi-monitor via AX coordinates). Falls back to
    /// InputDriver.scroll with explicit coordinates when x,y are provided.
    public static func scroll(
        direction: String,
        amount: Int?,
        appName: String?,
        x: Double?,
        y: Double?,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_scroll"
    ) -> ToolResult {
        _ = approvalRequestID
        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.scroll(
                app: appName,
                direction: direction,
                amount: amount,
                x: x,
                y: y,
                postconditions: inferredPressPostconditions(appName: appName)
            )
        )
    }

    static func performScroll(
        direction: String,
        amount: Int?,
        appName: String?,
        x: Double?,
        y: Double?
    ) -> ToolResult {
        let scrollAmount = amount ?? 3

        guard let scrollDir = mapScrollDirection(direction) else {
            return ToolResult(success: false, error: "Invalid direction: '\(direction)'")
        }

        // If explicit coordinates provided, use InputDriver directly
        if let x, let y {
            if let appName {
                _ = FocusManager.focus(appName: appName)
                Thread.sleep(forTimeInterval: 0.2)
            }
            do {
                try Element.scrollAt(
                    CGPoint(x: x, y: y),
                    direction: scrollDir,
                    amount: scrollAmount
                )
                return ToolResult(success: true, data: ["direction": direction, "amount": scrollAmount])
            } catch {
                return ToolResult(success: false, error: "Scroll failed: \(error)")
            }
        }

        // If app specified, use element-based scroll on the focused window.
        // AXorcist's element.scroll() calculates coordinates from the element's
        // frame, which auto-handles multi-monitor setups.
        if let appName {
            guard let appElement = AXScanner.appElement(for: appName) else {
                return ToolResult(success: false, error: "Application '\(appName)' not found")
            }
            guard let window = appElement.focusedWindow() ?? appElement.mainWindow() else {
                return ToolResult(success: false, error: "No window found for '\(appName)'")
            }

            // Find a scrollable area within the window (AXWebArea for browsers,
            // AXScrollArea for native apps, or the window itself)
            let scrollTarget = findScrollable(in: window) ?? window

            do {
                try scrollTarget.scroll(direction: scrollDir, amount: scrollAmount)
                return ToolResult(success: true, data: ["direction": direction, "amount": scrollAmount])
            } catch {
                // Fallback: try scrolling at the window's center
                if let frame = window.frame() {
                    let center = CGPoint(x: frame.midX, y: frame.midY)
                    do {
                        try Element.scrollAt(center, direction: scrollDir, amount: scrollAmount)
                        return ToolResult(success: true, data: ["direction": direction, "amount": scrollAmount])
                    } catch {
                        return ToolResult(success: false, error: "Scroll failed: \(error)")
                    }
                }
                return ToolResult(success: false, error: "Scroll failed: \(error)")
            }
        }

        // No app, no coordinates - scroll at current mouse position
        do {
            let lines = Double(scrollAmount)
            let deltaY: Double = (direction == "up" ? lines * 10 : -lines * 10)
            try InputDriver.scroll(deltaY: deltaY, at: nil)
            return ToolResult(success: true, data: ["direction": direction, "amount": scrollAmount])
        } catch {
            return ToolResult(success: false, error: "Scroll failed: \(error)")
        }
    }

    /// Find a scrollable element within a window (AXScrollArea or AXWebArea).
    private static func findScrollable(in element: Element, depth: Int = 0) -> Element? {
        guard depth < 5 else { return nil }
        let role = element.role() ?? ""
        if role == "AXScrollArea" || role == "AXWebArea" { return element }
        guard let children = element.children() else { return nil }
        for child in children {
            if let found = findScrollable(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private static func mapScrollDirection(_ direction: String) -> ScrollDirection? {
        switch direction.lowercased() {
        case "up": .up
        case "down": .down
        case "left": .left
        case "right": .right
        default: nil
        }
    }

    // MARK: - oracle_window

    /// Window management operations.
    public static func manageWindow(
        action: String,
        appName: String,
        windowTitle: String?,
        x: Double?, y: Double?,
        width: Double?, height: Double?,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_window"
    ) -> ToolResult {
        if action.lowercased() == "list" {
            return performWindowAction(
                action: action,
                appName: appName,
                windowTitle: windowTitle,
                x: x,
                y: y,
                width: width,
                height: height
            )
        }

        _ = approvalRequestID
        _ = taskID
        _ = toolName

        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.manageWindow(
                app: appName,
                action: action,
                windowTitle: windowTitle,
                x: x,
                y: y,
                width: width,
                height: height,
                postconditions: inferredFocusPostconditions(appName: appName, windowTitle: windowTitle)
            )
        )
    }

    static func performWindowAction(
        action: String,
        appName: String,
        windowTitle: String?,
        x: Double?, y: Double?,
        width: Double?, height: Double?
    ) -> ToolResult {
        guard let appElement = AXScanner.appElement(for: appName) else {
            return ToolResult(success: false, error: "Application '\(appName)' not found")
        }

        if action == "list" {
            guard let windows = appElement.windows() else {
                return ToolResult(success: true, data: ["windows": [] as [Any], "count": 0])
            }
            let infos: [[String: Any]] = windows.compactMap { win in
                var info: [String: Any] = [:]
                if let title = win.title() { info["title"] = title }
                if let pos = win.position() { info["position"] = ["x": Int(pos.x), "y": Int(pos.y)] }
                if let size = win.size() { info["size"] = ["width": Int(size.width), "height": Int(size.height)] }
                if let minimized = win.isMinimized() { info["minimized"] = minimized }
                if let fullscreen = win.isFullScreen() { info["fullscreen"] = fullscreen }
                return info.isEmpty ? nil : info
            }
            return ToolResult(success: true, data: ["windows": infos, "count": infos.count])
        }

        let window: Element? = if let windowTitle {
            appElement.windows()?.first { $0.title()?.localizedCaseInsensitiveContains(windowTitle) == true }
        } else {
            appElement.focusedWindow() ?? appElement.mainWindow()
        }

        guard let window else {
            return ToolResult(
                success: false,
                error: "Window not found in '\(appName)'",
                suggestion: "Use oracle_window with action:'list' to see windows"
            )
        }

        switch action.lowercased() {
        case "minimize":
            _ = window.minimizeWindow()
            return ToolResult(success: true, data: ["action": "minimize"])
        case "maximize":
            _ = window.maximizeWindow()
            return ToolResult(success: true, data: ["action": "maximize"])
        case "close":
            _ = window.closeWindow()
            return ToolResult(success: true, data: ["action": "close"])
        case "restore":
            _ = window.showWindow()
            return ToolResult(success: true, data: ["action": "restore"])
        case "move":
            guard let x, let y else {
                return ToolResult(success: false, error: "move requires x and y parameters")
            }
            _ = window.moveWindow(to: CGPoint(x: x, y: y))
            return ToolResult(success: true, data: ["action": "move", "x": x, "y": y])
        case "resize":
            guard let width, let height else {
                return ToolResult(success: false, error: "resize requires width and height parameters")
            }
            _ = window.resizeWindow(to: CGSize(width: width, height: height))
            return ToolResult(success: true, data: ["action": "resize", "width": width, "height": height])
        default:
            return ToolResult(success: false, error: "Unknown action: '\(action)'")
        }
    }

    // MARK: - Element Finding (shared helper)

    /// Find an element using content-root-first strategy with semantic depth.
    /// Searches AXWebArea first (in-page elements), then full app tree.
    private static func findElement(locator: Locator, appName: String?) -> Element? {
        guard let appElement = resolveAppElement(appName: appName) else { return nil }

        // Content-root-first: search AXWebArea, then full tree
        if let window = appElement.focusedWindow(),
           let webArea = AXScanner.findWebArea(in: window)
        {
            if let found = searchWithSemanticDepth(locator: locator, root: webArea) {
                return found
            }
        }

        // Full app tree fallback
        return searchWithSemanticDepth(locator: locator, root: appElement)
    }

    /// Search with semantic depth tunneling using AXorcist's Element.searchElements.
    /// Falls back to manual semantic-depth walk if AXorcist doesn't find it.
    private static func searchWithSemanticDepth(locator: Locator, root: Element) -> Element? {
        // Try AXorcist's built-in search first
        if let query = locator.computedNameContains {
            var options = ElementSearchOptions()
            options.maxDepth = OracleConstants.semanticDepthBudget
            if let roleCriteria = locator.criteria.first(where: { $0.attribute == "AXRole" }) {
                options.includeRoles = [roleCriteria.value]
            }
            if let found = root.findElement(matching: query, options: options) {
                return found
            }
        }

        // DOM ID search (bypasses depth limits)
        if let domIdCriteria = locator.criteria.first(where: { $0.attribute == "AXDOMIdentifier" }) {
            return findByDOMId(domIdCriteria.value, in: root, maxDepth: 50)
        }

        return nil
    }

    /// Resolve app name to Element.
    private static func resolveAppElement(appName: String?) -> Element? {
        if let appName {
            return AXScanner.appElement(for: appName)
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return Element.application(for: frontApp.processIdentifier)
    }

    // MARK: - Field Finding for oracle_type into

    /// Editable/input roles that the 'into' parameter should match against.
    /// When someone says into:"To", they mean a field labeled "To", not
    /// a link that says "Skip to content".
    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
        "AXSecureTextField",
    ]

    /// Find an editable field by name. Searches ALL matching elements and
    /// scores them, preferring editable roles and exact/prefix matches.
    /// This is the v1 SmartResolver pattern adapted for v2.
    private static func findEditableField(named query: String, appName: String?) -> Element? {
        guard let appElement = resolveAppElement(appName: appName) else { return nil }

        let queryLower = query.lowercased()

        // Search from content root first (web area), then full tree
        let searchRoot: Element
        if let window = appElement.focusedWindow(),
           let webArea = AXScanner.findWebArea(in: window)
        {
            searchRoot = webArea
        } else if let window = appElement.focusedWindow() {
            searchRoot = window
        } else {
            searchRoot = appElement
        }

        // Collect ALL matching elements with scores.
        // Uses semantic depth (empty layout containers cost 0) so we reach
        // Gmail compose fields at DOM depth 30+ within budget of 25.
        var candidates: [(element: Element, score: Int)] = []
        scoreFieldCandidates(
            element: searchRoot,
            queryLower: queryLower,
            candidates: &candidates,
            semanticDepth: 0,
            maxSemanticDepth: OracleConstants.semanticDepthBudget
        )

        // Return the highest-scoring candidate
        return candidates.max(by: { $0.score < $1.score })?.element
    }

    /// Layout roles that cost zero semantic depth (tunneled through).
    /// Same set used by oracle_read's semantic depth tunneling.
    private static let layoutRoles: Set<String> = [
        "AXGroup", "AXGenericElement", "AXSection", "AXDiv",
        "AXList", "AXLandmarkMain", "AXLandmarkNavigation",
        "AXLandmarkBanner", "AXLandmarkContentInfo",
    ]

    /// Walk the tree scoring elements as field candidates.
    /// Uses SEMANTIC depth (empty layout containers cost 0) so we can
    /// reach Gmail compose fields at DOM depth 30+ within budget of 25.
    private static func scoreFieldCandidates(
        element: Element,
        queryLower: String,
        candidates: inout [(element: Element, score: Int)],
        semanticDepth: Int,
        maxSemanticDepth: Int
    ) {
        guard semanticDepth <= maxSemanticDepth, candidates.count < 100 else { return }

        let role = element.role() ?? ""
        let titleLower = (element.title() ?? "").lowercased()
        let descLower = (element.descriptionText() ?? "").lowercased()
        let nameLower = (element.computedName() ?? "").lowercased()

        // Semantic depth: empty layout containers cost 0
        let hasContent = !titleLower.isEmpty || !descLower.isEmpty || !nameLower.isEmpty
        let isTunnel = layoutRoles.contains(role) && !hasContent
        let childSemanticDepth = isTunnel ? semanticDepth : semanticDepth + 1

        // Score: does this element's name match the query?
        var score = 0

        // Exact match on any name property
        if titleLower == queryLower || descLower == queryLower || nameLower == queryLower {
            score = 100
        }
        // Starts with query
        else if titleLower.hasPrefix(queryLower) || descLower.hasPrefix(queryLower) || nameLower.hasPrefix(queryLower) {
            score = 80
        }
        // Contains query
        else if titleLower.contains(queryLower) || descLower.contains(queryLower) || nameLower.contains(queryLower) {
            score = 60
        }

        if score > 0 {
            // Bonus for editable/interactive roles (the whole point of 'into')
            // High bonus (+50) ensures editable fields always beat links/buttons
            if editableRoles.contains(role) {
                score += 50
            }

            // Bonus for being on-screen (visible) - helps when multiple
            // compose windows exist (old draft vs current compose)
            if let pos = element.position(), let size = element.size() {
                let onScreen = NSScreen.screens.contains { screen in
                    screen.frame.intersects(CGRect(origin: pos, size: size))
                }
                if onScreen && size.width > 1 && size.height > 1 {
                    score += 20
                }
            }

            // Only include if score is reasonable
            if score >= 50 {
                candidates.append((element: element, score: score))
            }
        }

        // Recurse into children with semantic depth
        guard let children = element.children() else { return }
        for child in children {
            scoreFieldCandidates(
                element: child, queryLower: queryLower,
                candidates: &candidates,
                semanticDepth: childSemanticDepth,
                maxSemanticDepth: maxSemanticDepth
            )
        }
    }

    // MARK: - Readback Verification

    /// Read the current value of an element for verification.
    private static func readbackFromElement(_ element: Element) -> String {
        // Try raw AXValue (Chrome compatible)
        if let value = AXScanner.readValue(from: element), !value.isEmpty {
            return value.count > 200 ? String(value.prefix(200)) + "..." : value
        }
        // Try title (some fields expose typed text as title)
        if let title = element.title(), !title.isEmpty {
            return title.count > 200 ? String(title.prefix(200)) + "..." : title
        }
        // Try computedName
        if let name = element.computedName(), !name.isEmpty {
            return name.count > 200 ? String(name.prefix(200)) + "..." : name
        }
        return "(verification unavailable for this field type)"
    }

    private static func inferredClickPostconditions(
        query: String?,
        role: String?,
        domId: String?
    ) -> [Postcondition] {
        let target = domId ?? query
        guard let target else { return [] }

        let editableRoles = ["AXTextField", "AXTextArea", "AXComboBox"]
        if let role, editableRoles.contains(role) {
            return [
                .elementFocused(target),
            ]
        }

        return []
    }

    private static func inferredTypePostconditions(
        text: String,
        into: String?,
        domId: String?
    ) -> [Postcondition] {
        guard let target = domId ?? into else { return [] }
        return [
            .elementFocused(target),
            .elementValueEquals(target, text),
        ]
    }

    private static func inferredPressPostconditions(appName: String?) -> [Postcondition] {
        guard let appName else { return [] }
        return [.appFrontmost(appName)]
    }

    private static func inferredFocusPostconditions(
        appName: String,
        windowTitle: String?
    ) -> [Postcondition] {
        var conditions: [Postcondition] = [.appFrontmost(appName)]
        if let windowTitle {
            conditions.append(.windowTitleContains(windowTitle))
        }
        return conditions
    }

    // MARK: - DOM ID Search

    private static func findByDOMId(_ domId: String, in root: Element, maxDepth: Int) -> Element? {
        findByDOMIdWalk(element: root, domId: domId, depth: 0, maxDepth: maxDepth)
    }

    private static func findByDOMIdWalk(element: Element, domId: String, depth: Int, maxDepth: Int) -> Element? {
        guard depth < maxDepth else { return nil }
        if let elDomId = element.rawAttributeValue(named: "AXDOMIdentifier") as? String, elDomId == domId {
            return element
        }
        guard let children = element.children() else { return nil }
        for child in children {
            if let found = findByDOMIdWalk(element: child, domId: domId, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }

    // MARK: - Special Key Mapping

    private static func mapSpecialKey(_ key: String) -> SpecialKey? {
        switch key.lowercased() {
        case "return", "enter": .return
        case "tab": .tab
        case "escape", "esc": .escape
        case "space": .space
        case "delete", "backspace": .delete
        case "up": .up
        case "down": .down
        case "left": .left
        case "right": .right
        case "home": .home
        case "end": .end
        case "pageup": .pageUp
        case "pagedown": .pageDown
        case "f1": .f1;  case "f2": .f2;  case "f3": .f3
        case "f4": .f4;  case "f5": .f5;  case "f6": .f6
        case "f7": .f7;  case "f8": .f8;  case "f9": .f9
        case "f10": .f10; case "f11": .f11; case "f12": .f12
        default: nil
        }
    }
}
