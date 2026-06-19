import AppKit
import AXorcist
import CryptoKit
import Foundation

@MainActor
public enum ObservationBuilder {
    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox",
        "AXRadioButton", "AXPopUpButton", "AXComboBox", "AXMenuButton", "AXTab",
    ]

    public static func capture(
        appName: String? = nil,
        maxDepth: Int = 8,
        maxElements: Int = 50
    ) -> Observation {
        let runningApp: NSRunningApplication?
        if let appName {
            runningApp = AXScanner.findApp(named: appName)
        } else {
            runningApp = NSWorkspace.shared.frontmostApplication
        }

        guard let runningApp else {
            return Observation(
                app: appName ?? "Unknown",
                elements: []
            )
        }

        let appLabel = runningApp.localizedName ?? appName ?? "Unknown"
        guard let appElement = Element.application(for: runningApp.processIdentifier) else {
            return Observation(
                app: appLabel,
                elements: []
            )
        }

        let window = appElement.focusedWindow()
        let windowTitle = window?.title()
        let url = window.flatMap { AXScanner.findWebArea(in: $0) }.flatMap { AXScanner.readURL(from: $0) }

        var axElements: [UnifiedElement] = []
        if let window {
            collectInteractiveElements(
                from: window,
                appLabel: appLabel,
                windowTitle: windowTitle,
                results: &axElements,
                depth: 0,
                maxDepth: maxDepth,
                maxElements: maxElements
            )
        }

        let focused = appElement.focusedElement().map {
            unifiedElement(from: $0, appLabel: appLabel, windowTitle: windowTitle, source: .ax, confidence: 0.95)
        }

        let cdpElements = cdpUnifiedElements(
            appLabel: appLabel,
            windowTitle: windowTitle,
            maxElements: maxElements
        )
        let elements = ObservationFusion.fuse(ax: axElements, cdp: cdpElements, vision: [])

        return Observation(
            app: appLabel,
            windowTitle: windowTitle,
            url: url,
            focusedElementID: focused?.id,
            elements: prependFocusedIfNeeded(focused, to: elements)
        )
    }

    private static func prependFocusedIfNeeded(
        _ focused: UnifiedElement?,
        to elements: [UnifiedElement]
    ) -> [UnifiedElement] {
        guard let focused else { return elements }
        guard !elements.contains(where: { $0.id == focused.id }) else { return elements }
        return [focused] + elements
    }

    private static func collectInteractiveElements(
        from element: Element,
        appLabel: String,
        windowTitle: String?,
        results: inout [UnifiedElement],
        depth: Int,
        maxDepth: Int,
        maxElements: Int
    ) {
        collectInteractiveElementsInternal(
            from: element,
            appLabel: appLabel,
            windowTitle: windowTitle,
            results: &results,
            depth: depth,
            maxDepth: maxDepth,
            maxElements: maxElements
        )
    }

    private static func collectInteractiveElementsInternal(
        from element: Element,
        appLabel: String,
        windowTitle: String?,
        results: inout [UnifiedElement],
        depth: Int,
        maxDepth: Int,
        maxElements: Int
    ) {
        guard depth <= maxDepth, results.count < maxElements else { return }

        if let role = element.role(), interactiveRoles.contains(role) {
            results.append(
                unifiedElement(
                    from: element,
                    appLabel: appLabel,
                    windowTitle: windowTitle,
                    source: .ax,
                    confidence: 0.9
                )
            )
        }

        guard let children = element.children() else { return }
        for child in children {
            collectInteractiveElementsInternal(
                from: child,
                appLabel: appLabel,
                windowTitle: windowTitle,
                results: &results,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxElements: maxElements
            )
        }
    }

    private static func unifiedElement(
        from element: Element,
        appLabel: String,
        windowTitle: String?,
        source: ElementSource,
        confidence: Double
    ) -> UnifiedElement {
        let role = element.role()
        let value = AXScanner.readValue(from: element)
        let label = bestLabel(for: element, fallbackValue: value)
        let id = stableElementID(
            source: source,
            appLabel: appLabel,
            windowTitle: windowTitle,
            role: role,
            label: label,
            domID: readStringAttribute("AXDOMIdentifier", from: element),
            identifier: element.identifier(),
            frame: element.frame()
        )

        return UnifiedElement(
            id: id,
            source: source,
            role: role,
            label: label,
            value: value,
            frame: element.frame(),
            enabled: element.isEnabled() ?? true,
            visible: !(element.isHidden() ?? false),
            focused: element.isFocused() ?? false,
            confidence: confidence
        )
    }

    private static func bestLabel(for element: Element, fallbackValue: String?) -> String? {
        let candidates = [
            element.computedName(),
            element.title(),
            element.descriptionText(),
            fallbackValue,
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            if !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }

        return nil
    }

    private static func cdpUnifiedElements(
        appLabel: String,
        windowTitle: String?,
        maxElements: Int
    ) -> [UnifiedElement] {
        guard supportsCDP(for: appLabel),
              let elements = DOMScanner.listInteractiveElements()
        else {
            return []
        }

        return elements.prefix(maxElements).compactMap { candidate in
            let x = candidate["x"] as? Double ?? Double(candidate["x"] as? Int ?? 0)
            let y = candidate["y"] as? Double ?? Double(candidate["y"] as? Int ?? 0)
            let width = candidate["width"] as? Double ?? Double(candidate["width"] as? Int ?? 0)
            let height = candidate["height"] as? Double ?? Double(candidate["height"] as? Int ?? 0)
            let frame = CGRect(x: x, y: y, width: width, height: height)

            let role = firstNonEmptyString(
                candidate["role"] as? String,
                candidate["tag"] as? String
            )
            let value = firstNonEmptyString(
                candidate["value"] as? String,
                candidate["text"] as? String
            )
            let label = firstNonEmptyString(
                candidate["ariaLabel"] as? String,
                candidate["text"] as? String,
                candidate["placeholder"] as? String,
                candidate["title"] as? String,
                candidate["id"] as? String
            )
            let domID = firstNonEmptyString(candidate["id"] as? String)

            let id = stableElementID(
                source: .cdp,
                appLabel: appLabel,
                windowTitle: windowTitle,
                role: role,
                label: label,
                domID: domID,
                identifier: nil,
                frame: frame
            )

            return UnifiedElement(
                id: id,
                source: .cdp,
                role: role,
                label: label,
                value: value,
                frame: frame,
                enabled: candidate["enabled"] as? Bool ?? true,
                visible: candidate["visible"] as? Bool ?? true,
                focused: candidate["focused"] as? Bool ?? false,
                confidence: 0.75
            )
        }
    }

    private static func supportsCDP(for appLabel: String) -> Bool {
        let normalized = appLabel.lowercased()
        return normalized.contains("chrome")
    }

    private static func firstNonEmptyString(_ values: String?...) -> String? {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func stableElementID(
        source: ElementSource,
        appLabel: String,
        windowTitle: String?,
        role: String?,
        label: String?,
        domID: String?,
        identifier: String?,
        frame: CGRect?
    ) -> String {
        let frameKey: String
        if let frame {
            frameKey = "\(Int(frame.origin.x)):\(Int(frame.origin.y)):\(Int(frame.width)):\(Int(frame.height))"
        } else {
            frameKey = "no-frame"
        }

        let raw = [
            source.rawValue,
            appLabel,
            windowTitle ?? "",
            role ?? "",
            label ?? "",
            domID ?? "",
            identifier ?? "",
            frameKey,
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func readStringAttribute(_ name: String, from element: Element) -> String? {
        guard let value = element.rawAttributeValue(named: name) else { return nil }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private static func readDOMClasses(from element: Element) -> String? {
        guard let value = element.rawAttributeValue(named: "AXDOMClassList") else { return nil }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let values = value as? [String], !values.isEmpty {
            return values.joined(separator: " ")
        }
        return nil
    }
}
