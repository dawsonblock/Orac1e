import Foundation

public struct PageElementAttributes: Sendable {
    public let index: Int
    public let role: String?
    public let label: String?
    public let isClickable: Bool
    public let isVisible: Bool
    public let semanticLabel: String?
    public let position: (x: Int, y: Int)?

    public init(
        index: Int,
        role: String?,
        label: String?,
        isClickable: Bool,
        isVisible: Bool,
        semanticLabel: String? = nil,
        position: (x: Int, y: Int)? = nil
    ) {
        self.index = index
        self.role = role
        self.label = label
        self.isClickable = isClickable
        self.isVisible = isVisible
        self.semanticLabel = semanticLabel
        self.position = position
    }
}

public enum PageElementIndex {
    public static func lookup(_ index: Int, in snapshot: PageSnapshot) -> PageIndexedElement? {
        snapshot.indexedElements.first(where: { $0.index == index })
    }

    public static func actionableLabels(in snapshot: PageSnapshot) -> [String] {
        snapshot.indexedElements.compactMap(\.label)
    }

    public static func enrichedElements(in snapshot: PageSnapshot) -> [PageElementAttributes] {
        snapshot.indexedElements.map { element in
            PageElementAttributes(
                index: element.index,
                role: element.role,
                label: element.label,
                isClickable: isClickable(role: element.role),
                isVisible: true,
                semanticLabel: element.label
            )
        }
    }

    public static func clickableElements(in snapshot: PageSnapshot) -> [PageIndexedElement] {
        snapshot.indexedElements.filter { isClickable(role: $0.role) }
    }

    public static func elementsMatching(
        text: String,
        in snapshot: PageSnapshot
    ) -> [PageIndexedElement] {
        let lowered = text.lowercased()
        return snapshot.indexedElements.filter { element in
            guard let label = element.label else { return false }
            return label.lowercased().contains(lowered)
        }
    }

    private static func isClickable(role: String?) -> Bool {
        guard let role = role?.lowercased() else { return false }
        return role.contains("button")
            || role.contains("link")
            || role.contains("menuitem")
            || role.contains("tab")
            || role.contains("checkbox")
            || role.contains("radio")
    }
}
