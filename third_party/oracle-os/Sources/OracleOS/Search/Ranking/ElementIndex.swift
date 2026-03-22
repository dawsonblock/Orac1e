import Foundation

public final class ElementIndex {

    private var elements: [UnifiedElement] = []

    public init(elements: [UnifiedElement]) {
        self.elements = elements
    }

    public func all() -> [UnifiedElement] {
        elements
    }

    public func byRole(_ role: String) -> [UnifiedElement] {
        elements.filter { $0.role?.lowercased() == role.lowercased() }
    }

    public func byText(_ text: String) -> [UnifiedElement] {

        let query = text.lowercased()

        return elements.filter {
            ($0.label?.lowercased().contains(query) ?? false)
            ||
            ($0.value?.lowercased().contains(query) ?? false)
        }
    }
}
