// StateAbstractionEngine.swift — Compressed semantic UI state for planners.
//
// Converts raw observation elements (AX tree, DOM, vision) into compact
// ``SemanticElement`` values the planner can reason about without
// consuming large token budgets or dealing with noisy AX hierarchies.

import Foundation

// MARK: - Semantic element

/// Compact, planner-readable representation of a single interactive element.
public struct SemanticElement: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let kind: SemanticElementKind
    public let label: String
    public let interactable: Bool
    public let geometry: ElementGeometry?

    public init(
        id: String,
        kind: SemanticElementKind,
        label: String,
        interactable: Bool = true,
        geometry: ElementGeometry? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.interactable = interactable
        self.geometry = geometry
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "kind": kind.rawValue,
            "label": label,
            "interactable": interactable,
        ]
        if let geometry {
            result["geometry"] = [
                "x": geometry.x,
                "y": geometry.y,
                "width": geometry.width,
                "height": geometry.height,
            ]
        }
        return result
    }
}

/// Broad classification of what the element *is* from the planner's perspective.
public enum SemanticElementKind: String, Sendable, Codable, CaseIterable {
    case button
    case input
    case text
    case link
    case list
    case menu
    case dialog
    case tab
    case image
    case toggle
    case container
    case unknown
}

/// Bounding rectangle in screen coordinates.
public struct ElementGeometry: Sendable, Codable, Hashable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Compressed UI state

/// Minimal, planner-consumable snapshot of the current UI.
///
/// The planner should *never* read raw AX trees directly.
/// Instead it receives a ``CompressedUIState`` where each element is a
/// ``SemanticElement`` such as `Button("Send")` or `Input("Search")`.
public struct CompressedUIState: Sendable, Codable {
    public let app: String?
    public let windowTitle: String?
    public let url: String?
    public let elements: [SemanticElement]
    public let timestamp: TimeInterval

    public init(
        app: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        elements: [SemanticElement],
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.app = app
        self.windowTitle = windowTitle
        self.url = url
        self.elements = elements
        self.timestamp = timestamp
    }

    /// Interactable elements only.
    public var interactableElements: [SemanticElement] {
        elements.filter(\.interactable)
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "elements": elements.map { $0.toDict() },
            "timestamp": timestamp,
        ]
        if let app { result["app"] = app }
        if let windowTitle { result["window_title"] = windowTitle }
        if let url { result["url"] = url }
        return result
    }
}

// MARK: - Abstraction engine

/// Converts raw ``Observation`` and ``UnifiedElement`` arrays into a
/// ``CompressedUIState`` the planner can consume.
///
/// Responsibilities:
/// - Map raw AX / DOM roles to ``SemanticElementKind``
/// - Deduplicate elements that share role + label
/// - Attach intent-level labels
/// - Produce the minimal state object
public struct StateAbstractionEngine: Sendable {
    public init() {}

    /// Convert an ``Observation`` into a ``CompressedUIState``.
    public func compress(_ observation: Observation) -> CompressedUIState {
        let semantic = deduplicate(observation.elements.map(classify))
        return CompressedUIState(
            app: observation.app,
            windowTitle: observation.windowTitle,
            url: observation.url,
            elements: semantic
        )
    }

    // MARK: - Classification

    /// Map a single ``UnifiedElement`` to a ``SemanticElement``.
    public func classify(_ element: UnifiedElement) -> SemanticElement {
        let kind = mapRole(element.role)
        let label = bestLabel(for: element)
        let interactable = isInteractable(kind: kind, role: element.role)
        return SemanticElement(
            id: element.id,
            kind: kind,
            label: label,
            interactable: interactable,
            geometry: nil
        )
    }

    // MARK: - Internal helpers

    /// Map AX / DOM role string to ``SemanticElementKind``.
    func mapRole(_ role: String?) -> SemanticElementKind {
        guard let role = role?.lowercased() else { return .unknown }
        switch role {
        case let r where r.contains("button"):  return .button
        case let r where r.contains("textfield"),
             let r where r.contains("textarea"),
             let r where r.contains("combobox"),
             let r where r.contains("input"):    return .input
        case let r where r.contains("link"):     return .link
        case let r where r.contains("list"):     return .list
        case let r where r.contains("menu"):     return .menu
        case let r where r.contains("dialog"),
             let r where r.contains("sheet"),
             let r where r.contains("alert"):    return .dialog
        case let r where r.contains("tab"):      return .tab
        case let r where r.contains("image"):    return .image
        case let r where r.contains("checkbox"),
             let r where r.contains("switch"),
             let r where r.contains("toggle"):   return .toggle
        case let r where r.contains("statictext"),
             let r where r.contains("heading"):  return .text
        case let r where r.contains("group"),
             let r where r.contains("scroll"),
             let r where r.contains("layout"):   return .container
        default:                                  return .unknown
        }
    }

    /// Produce the best human-readable label for an element.
    func bestLabel(for element: UnifiedElement) -> String {
        if let label = element.label, !label.isEmpty {
            return label
        }
        if let role = element.role {
            return role
        }
        return element.id
    }

    /// Decide whether an element kind is directly interactable.
    func isInteractable(kind: SemanticElementKind, role: String?) -> Bool {
        switch kind {
        case .button, .input, .link, .menu, .tab, .toggle:
            return true
        case .text, .image, .container, .unknown:
            return false
        case .list, .dialog:
            return false
        }
    }

    /// Deduplicate elements that share the same kind + label, keeping
    /// the first occurrence.
    func deduplicate(_ elements: [SemanticElement]) -> [SemanticElement] {
        var seen = Set<String>()
        return elements.filter { element in
            let key = "\(element.kind.rawValue)|\(element.label)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}
