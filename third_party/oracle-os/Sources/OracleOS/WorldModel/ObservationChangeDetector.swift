import CoreGraphics
import Foundation

/// Detects fine-grained changes between two ``Observation`` snapshots.
///
/// Sits between perception and state abstraction in the runtime pipeline:
///
///     Observation (new)
///     ↓
///     ObservationChangeDetector.detect(previous:incoming:)
///     ↓
///     ObservationDelta
///     ↓
///     WorldModel.apply(delta)
///
/// By producing an ``ObservationDelta`` that captures only what changed,
/// downstream consumers avoid re-processing the entire UI tree each loop.
/// During long sessions with mostly stable UI this can reduce observation
/// processing cost by an order of magnitude.
public enum ObservationChangeDetector {

    /// Compare two observations and produce a delta describing every change.
    ///
    /// - Parameters:
    ///   - previous: The last observation processed by the world model.
    ///   - incoming: The freshly captured observation.
    /// - Returns: An ``ObservationDelta`` that is empty when nothing changed.
    public static func detect(
        previous: Observation,
        incoming: Observation
    ) -> ObservationDelta {
        // -- metadata changes --
        let appChange: ObservationDelta.StringChange? =
            previous.app != incoming.app
                ? .init(from: previous.app, to: incoming.app)
                : nil

        let windowChange: ObservationDelta.StringChange? =
            previous.windowTitle != incoming.windowTitle
                ? .init(from: previous.windowTitle, to: incoming.windowTitle)
                : nil

        let urlChange: ObservationDelta.StringChange? =
            previous.url != incoming.url
                ? .init(from: previous.url, to: incoming.url)
                : nil

        let focusChange: ObservationDelta.StringChange? =
            previous.focusedElementID != incoming.focusedElementID
                ? .init(from: previous.focusedElementID, to: incoming.focusedElementID)
                : nil

        // -- element-level diffing --
        let previousByID = Dictionary(
            previous.elements.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let incomingByID = Dictionary(
            incoming.elements.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let previousIDs = Set(previousByID.keys)
        let incomingIDs = Set(incomingByID.keys)

        // Added elements: present in incoming but not in previous.
        let addedIDs = incomingIDs.subtracting(previousIDs)
        let addedElements = addedIDs.compactMap { incomingByID[$0] }

        // Removed elements: present in previous but not in incoming.
        let removedIDs = Array(previousIDs.subtracting(incomingIDs))

        // Changed elements: present in both but with differing properties.
        let persistingIDs = previousIDs.intersection(incomingIDs)
        var changedElements: [ObservationDelta.ElementChange] = []

        for id in persistingIDs {
            guard let old = previousByID[id], let new = incomingByID[id] else { continue }
            let changed = diffProperties(old: old, new: new)
            if !changed.isEmpty {
                changedElements.append(
                    ObservationDelta.ElementChange(
                        elementID: id,
                        updatedElement: new,
                        changedProperties: changed
                    )
                )
            }
        }

        return ObservationDelta(
            applicationChanged: appChange,
            windowTitleChanged: windowChange,
            urlChanged: urlChange,
            focusChanged: focusChange,
            addedElements: addedElements,
            removedElementIDs: removedIDs,
            changedElements: changedElements
        )
    }

    // MARK: - Volatile property filtering

    /// Properties that change frequently but do not affect planning decisions.
    /// These are excluded from change detection to reduce noise.
    public static let volatileProperties: Set<ObservationDelta.ElementProperty> = [.frame, .confidence]

    /// Compare two elements, ignoring volatile properties that don't affect planning.
    public static func diffPlanningProperties(
        old: UnifiedElement,
        new: UnifiedElement
    ) -> Set<ObservationDelta.ElementProperty> {
        diffProperties(old: old, new: new).subtracting(volatileProperties)
    }

    // MARK: - Internal helpers

    /// Compare two elements with the same ID and return which properties differ.
    static func diffProperties(
        old: UnifiedElement,
        new: UnifiedElement
    ) -> Set<ObservationDelta.ElementProperty> {
        var changed = Set<ObservationDelta.ElementProperty>()

        if old.label != new.label { changed.insert(.label) }
        if old.value != new.value { changed.insert(.value) }
        if old.enabled != new.enabled { changed.insert(.enabled) }
        if old.visible != new.visible { changed.insert(.visible) }
        if old.focused != new.focused { changed.insert(.focused) }
        if old.role != new.role { changed.insert(.role) }
        if old.confidence != new.confidence { changed.insert(.confidence) }
        if !framesEqual(old.frame, new.frame) { changed.insert(.frame) }

        return changed
    }

    /// Compare two optional `CGRect` values with tolerance for floating-point noise.
    private static func framesEqual(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(l), .some(r)):
            return abs(l.origin.x - r.origin.x) < 1
                && abs(l.origin.y - r.origin.y) < 1
                && abs(l.width - r.width) < 1
                && abs(l.height - r.height) < 1
        default:
            return false
        }
    }
}
