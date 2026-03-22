import AppKit
import AXorcist
import ApplicationServices
import CoreGraphics
import Foundation
import ApplicationServices

public enum AXTimeoutConfiguration {
    public static func setGlobalTimeout(_ seconds: Float) {
        let systemElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemElement, seconds)
    }
}

public struct ElementSearchOptions: Sendable {
    public var maxDepth: Int
    public var caseInsensitive: Bool
    public var includeRoles: [String]?

    public init(
        maxDepth: Int = DEFAULT_MAX_DEPTH_SEARCH,
        caseInsensitive: Bool = true,
        includeRoles: [String]? = nil
    ) {
        self.maxDepth = maxDepth
        self.caseInsensitive = caseInsensitive
        self.includeRoles = includeRoles
    }
}

public enum MouseButton: Sendable {
    case left
    case right
    case middle

    fileprivate var cgButton: CGMouseButton {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case .middle:
            return .center
        }
    }

    fileprivate var mouseDownType: CGEventType {
        switch self {
        case .left:
            return .leftMouseDown
        case .right:
            return .rightMouseDown
        case .middle:
            return .otherMouseDown
        }
    }

    fileprivate var mouseUpType: CGEventType {
        switch self {
        case .left:
            return .leftMouseUp
        case .right:
            return .rightMouseUp
        case .middle:
            return .otherMouseUp
        }
    }
}

public enum ScrollDirection: String, Sendable {
    case up
    case down
    case left
    case right
}

public enum SpecialKey: String, Sendable {
    case `return`
    case tab
    case escape
    case space
    case delete
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12

    fileprivate var keyCode: CGKeyCode {
        switch self {
        case .return:
            return 36
        case .tab:
            return 48
        case .space:
            return 49
        case .delete:
            return 51
        case .escape:
            return 53
        case .f1:
            return 122
        case .f2:
            return 120
        case .f3:
            return 99
        case .f4:
            return 118
        case .f5:
            return 96
        case .f6:
            return 97
        case .f7:
            return 98
        case .f8:
            return 100
        case .f9:
            return 101
        case .f10:
            return 109
        case .f11:
            return 103
        case .f12:
            return 111
        case .home:
            return 115
        case .end:
            return 119
        case .pageUp:
            return 116
        case .pageDown:
            return 121
        case .left:
            return 123
        case .right:
            return 124
        case .down:
            return 125
        case .up:
            return 126
        }
    }
}

public enum InputDriver {
    public static func click(
        at point: CGPoint,
        button: MouseButton = .left,
        count: Int = 1
    ) throws {
        let clickCount = max(1, count)
        for index in 1...clickCount {
            guard let down = CGEvent(mouseEventSource: nil, mouseType: button.mouseDownType, mouseCursorPosition: point, mouseButton: button.cgButton),
                  let up = CGEvent(mouseEventSource: nil, mouseType: button.mouseUpType, mouseCursorPosition: point, mouseButton: button.cgButton)
            else {
                throw AXCompatibilityError.eventCreationFailed("mouse click")
            }
            down.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }

    public static func scroll(deltaY: Double, at point: CGPoint?) throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: Int32(deltaY.rounded()),
            wheel2: 0,
            wheel3: 0
        ) else {
            throw AXCompatibilityError.eventCreationFailed("scroll")
        }
        if let point {
            event.location = point
        }
        event.post(tap: .cghidEventTap)
    }
}

@MainActor
public extension Element {
    static func application(for pid: pid_t) -> Element? {
        Element(AXUIElementCreateApplication(pid))
    }

    static func elementAtPoint(_ point: CGPoint) -> Element? {
        let systemElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemElement,
            Float(point.x),
            Float(point.y),
            &element
        )
        guard result == .success, let element else {
            return nil
        }
        return Element(element)
    }

    func role() -> String? {
        stringProperty { logs in
            role(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
        }
    }

    func subrole() -> String? {
        stringProperty { logs in
            subrole(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
        }
    }

    func title() -> String? {
        stringProperty { logs in
            title(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
        }
    }

    func descriptionText() -> String? {
        stringProperty { logs in
            description(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
        }
    }

    func help() -> String? {
        stringProperty { logs in
            help(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
        }
    }

    func identifier() -> String? {
        stringProperty { logs in
            identifier(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
        }
    }

    func value() -> Any? {
        var logs: [String] = []
        return value(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func isEnabled() -> Bool? {
        boolProperty { logs in
            isEnabled(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
        }
    }

    func isFocused() -> Bool? {
        boolProperty { logs in
            isFocused(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
        }
    }

    func isHidden() -> Bool? {
        boolProperty { logs in
            isHidden(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
        }
    }

    func isElementBusy() -> Bool? {
        boolProperty { logs in
            isElementBusy(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
        }
    }

    func isIgnored() -> Bool {
        var logs: [String] = []
        return isIgnored(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func parent() -> Element? {
        var logs: [String] = []
        return parent(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func children() -> [Element]? {
        var logs: [String] = []
        return children(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func windows() -> [Element]? {
        var logs: [String] = []
        return windows(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func mainWindow() -> Element? {
        var logs: [String] = []
        return mainWindow(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func focusedWindow() -> Element? {
        var logs: [String] = []
        return focusedWindow(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func focusedElement() -> Element? {
        var logs: [String] = []
        return focusedElement(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func supportedActions() -> [String]? {
        var logs: [String] = []
        return supportedActions(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func computedName() -> String? {
        var logs: [String] = []
        return computedName(isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func rawAttributeValue(named attributeName: String) -> CFTypeRef? {
        var logs: [String] = []
        return rawAttributeValue(named: attributeName, isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func generatePathString(upTo ancestor: Element? = nil) -> String {
        var logs: [String] = []
        return generatePathString(upTo: ancestor, isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func invokeAction(_ actionName: String) throws {
        let result = AXUIElementPerformAction(underlyingElement, actionName as CFString)
        guard result == .success else {
            throw AXCompatibilityError.actionFailed(actionName, result.rawValue)
        }
    }

    func isActionSupported(_ actionName: String) -> Bool {
        var logs: [String] = []
        return isActionSupported(actionName, isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    func position() -> CGPoint? {
        typedAttribute(.position)
    }

    func size() -> CGSize? {
        typedAttribute(.size)
    }

    func frame() -> CGRect? {
        guard let position = position(), let size = size() else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    func selectedText() -> String? {
        typedAttribute(.selectedText)
    }

    func numberOfCharacters() -> Int? {
        typedAttribute(.numberOfCharacters)
    }

    func placeholderValue() -> String? {
        rawAttributeValue(named: "AXPlaceholderValue") as? String
    }

    func isMinimized() -> Bool? {
        typedAttribute(.minimized)
    }

    func isFullScreen() -> Bool? {
        rawAttributeValue(named: "AXFullScreen") as? Bool
    }

    func isModal() -> Bool? {
        typedAttribute(.modal)
    }

    func url() -> URL? {
        if let url = rawAttributeValue(named: "AXURL") as? URL {
            return url
        }
        if let string = rawAttributeValue(named: "AXURL") as? String {
            return URL(string: string)
        }
        return nil
    }

    func isEditable() -> Bool {
        if let editable = rawAttributeValue(named: "AXEditable") as? Bool {
            return editable
        }
        let editableRoles: Set<String> = [
            "AXTextField",
            "AXTextArea",
            "AXSearchField",
            "AXSecureTextField",
            "AXComboBox",
        ]
        return editableRoles.contains(role() ?? "")
    }

    func isActionable() -> Bool {
        if isEnabled() == false || isHidden() == true {
            return false
        }
        if isEditable() {
            return true
        }
        let role = role() ?? ""
        let actionableRoles: Set<String> = [
            "AXButton",
            "AXLink",
            "AXCheckBox",
            "AXRadioButton",
            "AXPopUpButton",
            "AXMenuButton",
            "AXDisclosureTriangle",
        ]
        if actionableRoles.contains(role) {
            return true
        }
        return (supportedActions() ?? []).contains("AXPress")
    }

    func setMessagingTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(underlyingElement, seconds)
    }

    func windowsWithTimeout(timeout: Float) -> [Element]? {
        setMessagingTimeout(timeout)
        defer { setMessagingTimeout(0) }
        return windows()
    }

    func isAttributeSettable(named name: String) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(underlyingElement, name as CFString, &settable)
        return result == .success && settable.boolValue
    }

    @discardableResult
    func setValue(_ value: Any, forAttribute name: String) -> Bool {
        guard let cfValue = Self.makeCFTypeRef(value) else {
            return false
        }
        return AXUIElementSetAttributeValue(underlyingElement, name as CFString, cfValue) == .success
    }

    func click(button: MouseButton = .left, clickCount: Int = 1) throws {
        if button == .left, clickCount == 1, isActionSupported("AXPress") {
            try invokeAction("AXPress")
            return
        }
        guard let frame = frame() else {
            throw AXCompatibilityError.missingFrame
        }
        try InputDriver.click(at: CGPoint(x: frame.midX, y: frame.midY), button: button, count: clickCount)
    }

    @discardableResult
    func focusWindow() -> Bool {
        do {
            try invokeAction("AXRaise")
            _ = setValue(true, forAttribute: "AXMain")
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func minimizeWindow() -> Bool {
        setValue(true, forAttribute: "AXMinimized")
    }

    @discardableResult
    func maximizeWindow() -> Bool {
        if let zoomButton = buttonElement(.zoomButton) {
            do {
                try zoomButton.click()
                return true
            } catch {
                return false
            }
        }
        return setValue(true, forAttribute: "AXFullScreen")
    }

    @discardableResult
    func closeWindow() -> Bool {
        guard let closeButton = buttonElement(.closeButton) else {
            return false
        }
        do {
            try closeButton.click()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func showWindow() -> Bool {
        if isMinimized() == true {
            _ = setValue(false, forAttribute: ApplicationServices.kAXMinimizedAttribute)
        }
        return focusWindow()
    }

    @discardableResult
    func moveWindow(to point: CGPoint) -> Bool {
        setValue(point, forAttribute: ApplicationServices.kAXPositionAttribute)
    }

    @discardableResult
    func resizeWindow(to size: CGSize) -> Bool {
        setValue(size, forAttribute: ApplicationServices.kAXSizeAttribute)
    }

    func scroll(direction: ScrollDirection, amount: Int) throws {
        let point = frame().map { CGPoint(x: $0.midX, y: $0.midY) }
        switch direction {
        case .up:
            try InputDriver.scroll(deltaY: Double(amount * 10), at: point)
        case .down:
            try InputDriver.scroll(deltaY: Double(-amount * 10), at: point)
        case .left, .right:
            let delta = Int32((direction == .right ? 1 : -1) * max(1, amount) * 10)
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: 0,
                wheel2: delta,
                wheel3: 0
            ) else {
                throw AXCompatibilityError.eventCreationFailed("horizontal scroll")
            }
            if let point {
                event.location = point
            }
            event.post(tap: .cghidEventTap)
        }
    }

    static func scrollAt(_ point: CGPoint, direction: ScrollDirection, amount: Int) throws {
        switch direction {
        case .up:
            try InputDriver.scroll(deltaY: Double(amount * 10), at: point)
        case .down:
            try InputDriver.scroll(deltaY: Double(-amount * 10), at: point)
        case .left, .right:
            let delta = Int32((direction == .right ? 1 : -1) * max(1, amount) * 10)
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: 0,
                wheel2: delta,
                wheel3: 0
            ) else {
                throw AXCompatibilityError.eventCreationFailed("horizontal scroll")
            }
            event.location = point
            event.post(tap: .cghidEventTap)
        }
    }

    static func typeText(_ text: String, delay: TimeInterval = 0) throws {
        for character in text {
            let units = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else {
                throw AXCompatibilityError.eventCreationFailed("text input")
            }
            units.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: baseAddress)
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
    }

    static func typeKey(_ key: SpecialKey) throws {
        try postKey(key.keyCode, flags: [])
    }

    static func performHotkey(keys: [String]) throws {
        let lowered = keys.map { $0.lowercased() }
        let flags = lowered.reduce(into: CGEventFlags()) { partial, token in
            switch token {
            case "cmd", "command":
                partial.insert(.maskCommand)
            case "shift":
                partial.insert(.maskShift)
            case "option", "alt":
                partial.insert(.maskAlternate)
            case "ctrl", "control":
                partial.insert(.maskControl)
            default:
                break
            }
        }

        guard let mainKey = lowered.last(where: { !Self.isModifierKey($0) }) else {
            throw AXCompatibilityError.unsupportedKey(keys.joined(separator: "+"))
        }

        if let specialKey = Self.specialKey(for: mainKey) {
            try postKey(specialKey.keyCode, flags: flags)
            return
        }

        guard let keyCode = Self.keyCode(for: mainKey) else {
            throw AXCompatibilityError.unsupportedKey(mainKey)
        }
        try postKey(keyCode, flags: flags)
    }

    func searchElements(matching query: String, options: ElementSearchOptions = ElementSearchOptions()) -> [Element] {
        var results: [Element] = []
        collectMatches(
            query: query,
            options: options,
            depth: 0,
            results: &results
        )
        return results
    }

    func searchElements(byRole role: String, options: ElementSearchOptions = ElementSearchOptions()) -> [Element] {
        var results: [Element] = []
        collectRoleMatches(
            role: role,
            options: options,
            depth: 0,
            results: &results
        )
        return results
    }

    func findElement(matching query: String, options: ElementSearchOptions = ElementSearchOptions()) -> Element? {
        searchElements(matching: query, options: options).first
    }

    func findElement(byIdentifier identifier: String) -> Element? {
        if self.identifier()?.localizedCaseInsensitiveCompare(identifier) == .orderedSame {
            return self
        }
        for child in children() ?? [] {
            if let found = child.findElement(byIdentifier: identifier) {
                return found
            }
        }
        return nil
    }

    private func typedAttribute<T>(_ attribute: Attribute<T>) -> T? {
        var logs: [String] = []
        return self.attribute(attribute, isDebugLoggingEnabled: false, currentDebugLogs: &logs)
    }

    private func buttonElement(_ attribute: Attribute<AXUIElement?>) -> Element? {
        var logs: [String] = []
        guard let element = self.attribute(attribute, isDebugLoggingEnabled: false, currentDebugLogs: &logs) ?? nil else {
            return nil
        }
        return Element(element)
    }

    private func stringProperty(_ getter: (inout [String]) -> String?) -> String? {
        var logs: [String] = []
        return getter(&logs)
    }

    private func boolProperty(_ getter: (inout [String]) -> Bool?) -> Bool? {
        var logs: [String] = []
        return getter(&logs)
    }

    private func collectMatches(
        query: String,
        options: ElementSearchOptions,
        depth: Int,
        results: inout [Element]
    ) {
        guard depth <= options.maxDepth else { return }
        if matches(query: query, options: options) {
            results.append(self)
        }
        for child in children() ?? [] {
            child.collectMatches(query: query, options: options, depth: depth + 1, results: &results)
        }
    }

    private func collectRoleMatches(
        role targetRole: String,
        options: ElementSearchOptions,
        depth: Int,
        results: inout [Element]
    ) {
        guard depth <= options.maxDepth else { return }
        let currentRole = role() ?? ""
        let lhs = options.caseInsensitive ? currentRole.lowercased() : currentRole
        let rhs = options.caseInsensitive ? targetRole.lowercased() : targetRole
        if lhs == rhs {
            results.append(self)
        }
        for child in children() ?? [] {
            child.collectRoleMatches(role: targetRole, options: options, depth: depth + 1, results: &results)
        }
    }

    private func matches(query: String, options: ElementSearchOptions) -> Bool {
        if let includeRoles = options.includeRoles, includeRoles.isEmpty == false {
            guard let role = role(), includeRoles.contains(where: { Self.matches($0, against: role, caseInsensitive: true) }) else {
                return false
            }
        }

        let haystacks = [
            computedName(),
            title(),
            descriptionText(),
            identifier(),
            value() as? String,
        ].compactMap { $0 }

        return haystacks.contains {
            Self.matches(query, against: $0, caseInsensitive: options.caseInsensitive)
        }
    }

    private static func makeCFTypeRef(_ value: Any) -> CFTypeRef? {
        switch value {
        case let value as String:
            return value as CFString
        case let value as NSString:
            return value
        case let value as Bool:
            return NSNumber(value: value)
        case let value as NSNumber:
            return value
        case let value as CGPoint:
            var point = value
            return AXValueCreate(.cgPoint, &point)
        case let value as CGSize:
            var size = value
            return AXValueCreate(.cgSize, &size)
        case let value as CGRect:
            var rect = value
            return AXValueCreate(.cgRect, &rect)
        default:
            return nil
        }
    }

    private static func matches(_ query: String, against value: String, caseInsensitive: Bool) -> Bool {
        let lhs = caseInsensitive ? value.lowercased() : value
        let rhs = caseInsensitive ? query.lowercased() : query
        return lhs.contains(rhs)
    }

    private static func isModifierKey(_ key: String) -> Bool {
        switch key {
        case "cmd", "command", "shift", "option", "alt", "ctrl", "control":
            return true
        default:
            return false
        }
    }

    private static func specialKey(for token: String) -> SpecialKey? {
        switch token {
        case "return", "enter":
            return .return
        case "tab":
            return .tab
        case "escape", "esc":
            return .escape
        case "space":
            return .space
        case "delete", "backspace":
            return .delete
        case "up":
            return .up
        case "down":
            return .down
        case "left":
            return .left
        case "right":
            return .right
        case "home":
            return .home
        case "end":
            return .end
        case "pageup":
            return .pageUp
        case "pagedown":
            return .pageDown
        case "f1":
            return .f1
        case "f2":
            return .f2
        case "f3":
            return .f3
        case "f4":
            return .f4
        case "f5":
            return .f5
        case "f6":
            return .f6
        case "f7":
            return .f7
        case "f8":
            return .f8
        case "f9":
            return .f9
        case "f10":
            return .f10
        case "f11":
            return .f11
        case "f12":
            return .f12
        default:
            return nil
        }
    }

    private static func keyCode(for token: String) -> CGKeyCode? {
        switch token {
        case "a":
            return 0
        case "s":
            return 1
        case "d":
            return 2
        case "f":
            return 3
        case "h":
            return 4
        case "g":
            return 5
        case "z":
            return 6
        case "x":
            return 7
        case "c":
            return 8
        case "v":
            return 9
        case "b":
            return 11
        case "q":
            return 12
        case "w":
            return 13
        case "e":
            return 14
        case "r":
            return 15
        case "y":
            return 16
        case "t":
            return 17
        case "1":
            return 18
        case "2":
            return 19
        case "3":
            return 20
        case "4":
            return 21
        case "6":
            return 22
        case "5":
            return 23
        case "=":
            return 24
        case "9":
            return 25
        case "7":
            return 26
        case "-":
            return 27
        case "8":
            return 28
        case "0":
            return 29
        case "]":
            return 30
        case "o":
            return 31
        case "u":
            return 32
        case "[":
            return 33
        case "i":
            return 34
        case "p":
            return 35
        case "l":
            return 37
        case "j":
            return 38
        case "'":
            return 39
        case "k":
            return 40
        case ";":
            return 41
        case "\\":
            return 42
        case ",":
            return 43
        case "/":
            return 44
        case "n":
            return 45
        case "m":
            return 46
        case ".":
            return 47
        case "`":
            return 50
        default:
            return nil
        }
    }

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            throw AXCompatibilityError.eventCreationFailed("key event")
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

private enum AXCompatibilityError: LocalizedError {
    case eventCreationFailed(String)
    case missingFrame
    case unsupportedKey(String)
    case actionFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .eventCreationFailed(let operation):
            return "Failed to create \(operation) event"
        case .missingFrame:
            return "Element has no screen frame"
        case .unsupportedKey(let key):
            return "Unsupported key '\(key)'"
        case .actionFailed(let action, let code):
            return "AX action '\(action)' failed with code \(code)"
        }
    }
}
