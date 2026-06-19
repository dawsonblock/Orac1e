import Foundation

/// Computes the difference between two world states so the ``WorldStateModel``
/// can be updated incrementally instead of replaced wholesale.
///
/// `StateDiffEngine` is the **mandatory intermediary** for all world-state
/// updates.  Every mutation to the committed world model must be expressed as
/// a ``StateDiff`` produced by this engine, ensuring a consistent audit trail
/// and enabling downstream consumers to react to fine-grained changes.
///
/// Delta-based updates are strongly preferred over whole-tree rebuilds.  When
/// a previous ``Observation`` is available the engine delegates to
/// ``ObservationChangeDetector`` for element-level diffing, which avoids
/// the cost of reconstructing the entire world model from scratch.
public enum StateDiffEngine {

    /// Compute a diff between the current model snapshot and a new observation.
    public static func diff(
        current: WorldModelSnapshot,
        incoming: WorldState
    ) -> StateDiff {
        diff(current: current, incoming: incoming, previousObservation: nil)
    }

    /// Compute a diff that includes element-level changes when a previous
    /// ``Observation`` is available.
    ///
    /// When `previousObservation` is supplied the engine delegates to
    /// ``ObservationChangeDetector`` to produce a fine-grained
    /// ``ObservationDelta`` describing exactly which elements were added,
    /// removed, or mutated.  Downstream consumers can use the delta to
    /// patch the world model instead of rebuilding it from scratch.
    public static func diff(
        current: WorldModelSnapshot,
        incoming: WorldState,
        previousObservation: Observation?
    ) -> StateDiff {
        var changes: [StateDiff.Change] = []

        if current.activeApplication != incoming.observation.app {
            changes.append(.applicationChanged(
                from: current.activeApplication,
                to: incoming.observation.app
            ))
        }

        if current.windowTitle != incoming.observation.windowTitle {
            changes.append(.windowTitleChanged(
                from: current.windowTitle,
                to: incoming.observation.windowTitle
            ))
        }

        if current.url != incoming.observation.url {
            changes.append(.urlChanged(
                from: current.url,
                to: incoming.observation.url
            ))
        }

        let incomingModalPresent = incoming.planningState.modalClass != nil
        if current.modalPresent != incomingModalPresent {
            changes.append(.modalStateChanged(present: incomingModalPresent))
        }

        let incomingElementCount = incoming.observation.elements.count
        if current.visibleElementCount != incomingElementCount {
            changes.append(.elementCountChanged(
                from: current.visibleElementCount,
                to: incomingElementCount
            ))
        }

        if let repo = incoming.repositorySnapshot {
            if current.activeBranch != repo.activeBranch {
                changes.append(.branchChanged(
                    from: current.activeBranch,
                    to: repo.activeBranch
                ))
            }
            if current.isGitDirty != repo.isGitDirty {
                changes.append(.gitDirtyChanged(isDirty: repo.isGitDirty))
            }
        }

        if current.observationHash != incoming.observationHash {
            changes.append(.observationHashChanged(
                from: current.observationHash,
                to: incoming.observationHash
            ))
        }

        // Element-level delta when a previous observation is available.
        let observationDelta: ObservationDelta?
        if let previousObservation {
            let delta = ObservationChangeDetector.detect(
                previous: previousObservation,
                incoming: incoming.observation
            )
            observationDelta = delta.isEmpty ? nil : delta
        } else {
            observationDelta = nil
        }

        return StateDiff(
            changes: changes,
            incomingWorldState: incoming,
            observationDelta: observationDelta,
            timestamp: Date()
        )
    }
}

/// Represents the set of changes between two world model states.
public struct StateDiff: Sendable {
    public let changes: [Change]
    public let incomingWorldState: WorldState
    /// Fine-grained element-level delta, available when the previous
    /// ``Observation`` was supplied to ``StateDiffEngine``.
    public let observationDelta: ObservationDelta?
    public let timestamp: Date

    public var isEmpty: Bool { changes.isEmpty && (observationDelta?.isEmpty ?? true) }

    public var changeCount: Int { changes.count + (observationDelta?.changeCount ?? 0) }

    public init(
        changes: [Change],
        incomingWorldState: WorldState,
        observationDelta: ObservationDelta? = nil,
        timestamp: Date
    ) {
        self.changes = changes
        self.incomingWorldState = incomingWorldState
        self.observationDelta = observationDelta
        self.timestamp = timestamp
    }

    public enum Change: Sendable {
        case applicationChanged(from: String?, to: String?)
        case windowTitleChanged(from: String?, to: String?)
        case urlChanged(from: String?, to: String?)
        case modalStateChanged(present: Bool)
        case elementCountChanged(from: Int, to: Int)
        case branchChanged(from: String?, to: String?)
        case gitDirtyChanged(isDirty: Bool)
        case observationHashChanged(from: String?, to: String?)
    }
}
