import Foundation

/// Represents the fine-grained set of changes between two ``Observation``
/// snapshots at the individual element level.
///
/// The delta pipeline replaces full-observation rebuilds:
///
///     previous observation
///     ↓
///     ObservationChangeDetector
///     ↓
///     ObservationDelta          ← this type
///     ↓
///     WorldModel.apply(delta)
///
/// During long autonomous runs only a small fraction of UI elements change
/// each loop iteration.  By capturing exactly *what* changed the system
/// avoids re-processing thousands of unchanged elements.
public struct ObservationDelta: Sendable {

    // MARK: - Metadata changes

    /// Application name changed (or was set / cleared).
    public let applicationChanged: StringChange?

    /// Window title changed.
    public let windowTitleChanged: StringChange?

    /// URL changed (e.g. browser navigation).
    public let urlChanged: StringChange?

    /// The focused element ID changed.
    public let focusChanged: StringChange?

    // MARK: - Element-level changes

    /// Elements that appeared in the new observation but were absent before.
    public let addedElements: [UnifiedElement]

    /// Element IDs that were present before but are now missing.
    public let removedElementIDs: [String]

    /// Elements whose ID persisted but one or more properties changed.
    public let changedElements: [ElementChange]

    /// `true` when none of the fields carry any information.
    public var isEmpty: Bool {
        applicationChanged == nil
            && windowTitleChanged == nil
            && urlChanged == nil
            && focusChanged == nil
            && addedElements.isEmpty
            && removedElementIDs.isEmpty
            && changedElements.isEmpty
    }

    /// Total number of discrete changes captured.
    public var changeCount: Int {
        var count = 0
        if applicationChanged != nil { count += 1 }
        if windowTitleChanged != nil { count += 1 }
        if urlChanged != nil { count += 1 }
        if focusChanged != nil { count += 1 }
        count += addedElements.count
        count += removedElementIDs.count
        count += changedElements.count
        return count
    }

    public init(
        applicationChanged: StringChange? = nil,
        windowTitleChanged: StringChange? = nil,
        urlChanged: StringChange? = nil,
        focusChanged: StringChange? = nil,
        addedElements: [UnifiedElement] = [],
        removedElementIDs: [String] = [],
        changedElements: [ElementChange] = []
    ) {
        self.applicationChanged = applicationChanged
        self.windowTitleChanged = windowTitleChanged
        self.urlChanged = urlChanged
        self.focusChanged = focusChanged
        self.addedElements = addedElements
        self.removedElementIDs = removedElementIDs
        self.changedElements = changedElements
    }

    // MARK: - Nested types

    /// A change to an optional string field.
    public struct StringChange: Sendable, Equatable {
        public let from: String?
        public let to: String?

        public init(from: String?, to: String?) {
            self.from = from
            self.to = to
        }
    }

    /// Describes how a persisting element's properties changed.
    public struct ElementChange: Sendable {
        public let elementID: String
        public let updatedElement: UnifiedElement
        public let changedProperties: Set<ElementProperty>

        public init(
            elementID: String,
            updatedElement: UnifiedElement,
            changedProperties: Set<ElementProperty>
        ) {
            self.elementID = elementID
            self.updatedElement = updatedElement
            self.changedProperties = changedProperties
        }
    }

    /// Which property of a ``UnifiedElement`` changed.
    public enum ElementProperty: String, Sendable, Hashable, CaseIterable {
        case label
        case value
        case enabled
        case visible
        case focused
        case frame
        case role
        case confidence
    }
}
