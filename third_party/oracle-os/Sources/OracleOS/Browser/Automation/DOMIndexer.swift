import Foundation

public struct DOMElementSignal: Sendable {
    public let elementID: String
    public let text: String
    public let role: String
    public let isVisible: Bool
    public let isClickable: Bool
    public let formRelationship: String?
    public let sectionContext: String?
    public let confidence: Double

    public init(
        elementID: String,
        text: String,
        role: String,
        isVisible: Bool = true,
        isClickable: Bool = true,
        formRelationship: String? = nil,
        sectionContext: String? = nil,
        confidence: Double = 1.0
    ) {
        self.elementID = elementID
        self.text = text
        self.role = role
        self.isVisible = isVisible
        self.isClickable = isClickable
        self.formRelationship = formRelationship
        self.sectionContext = sectionContext
        self.confidence = confidence
    }
}

public enum DOMIndexer {

    public static func index(snapshot: PageSnapshot) -> [DOMElementSignal] {
        snapshot.indexedElements.compactMap { element in
            guard let label = element.label, !label.isEmpty else {
                return nil
            }
            return DOMElementSignal(
                elementID: element.id,
                text: label,
                role: element.role ?? "unknown",
                isVisible: element.visible,
                isClickable: isClickableRole(element.role),
                formRelationship: formRelationship(for: element),
                sectionContext: sectionContext(for: element),
                confidence: element.visible ? 1.0 : 0.0
            )
        }
    }

    public static func richIndex(snapshot: PageSnapshot) -> [DOMElementSignal] {
        index(snapshot: snapshot).filter { signal in
            signal.isVisible && signal.confidence > 0.1
        }
    }

    private static func isClickableRole(_ role: String?) -> Bool {
        guard let role = role?.lowercased() else { return false }
        let clickableRoles = ["axbutton", "button", "axlink", "link", "axmenuitem", "menuitem",
                              "axtextfield", "textfield", "axcheckbox", "checkbox", "axradiobutton",
                              "tab", "axtab", "axcombobox", "combobox"]
        return clickableRoles.contains(role)
    }

    private static func formRelationship(for element: PageIndexedElement) -> String? {
        guard let role = element.role?.lowercased() else { return nil }
        let formRoles = ["axtextfield", "textfield", "axcheckbox", "checkbox",
                         "axradiobutton", "axcombobox", "combobox", "textarea"]
        if formRoles.contains(role) {
            return "form-input"
        }
        if role == "axbutton" || role == "button" {
            if let label = element.label?.lowercased(),
               label.contains("submit") || label.contains("save") || label.contains("send") {
                return "form-submit"
            }
        }
        return nil
    }

    private static func sectionContext(for element: PageIndexedElement) -> String? {
        guard let label = element.label else { return nil }
        if label.lowercased().contains("nav") || label.lowercased().contains("menu") {
            return "navigation"
        }
        if label.lowercased().contains("header") {
            return "header"
        }
        if label.lowercased().contains("footer") {
            return "footer"
        }
        return nil
    }
}
