import Foundation

/// A persistent internal model of the agent's environment that is updated
/// incrementally rather than rebuilt from scratch each loop iteration.
///
/// The world model sits between perception and planning:
///
///     perception → world model update → planning → execution
///
/// By maintaining a stable representation the planner reasons over richer
/// context and can simulate future states before committing to actions.
///
/// ## State Layers
///
/// The world model conceptually operates across three layers:
///
/// 1. **Observed state** — raw perception data produced by
///    ``ObservationBuilder`` each loop tick.
/// 2. **Predicted state** — a simulated projection computed by
///    ``PlanSimulator`` *before* committing an action.
/// 3. **Committed world state** — the model's ``snapshot``, the **ONLY**
///    layer that planners should read from when making decisions.
public final class WorldStateModel: @unchecked Sendable {
    private let lock = NSLock()
    private var current: WorldModelSnapshot
    private var history: [WorldModelSnapshot] = []
    private let maxHistory: Int

    public init(maxHistory: Int = 20) {
        self.current = WorldModelSnapshot()
        self.maxHistory = maxHistory
    }

    public init(snapshot: WorldModelSnapshot, maxHistory: Int = 20) {
        self.current = snapshot
        self.maxHistory = maxHistory
    }

    /// The committed world state — the **authoritative** snapshot that planners read.
    ///
    /// This is the only layer that downstream decision-making should depend on.
    public var snapshot: WorldModelSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Apply a diff produced by ``StateDiffEngine`` to advance the model.
    ///
    /// This is the **only** sanctioned path for incremental state advancement.
    /// All world-model mutations flow through delta-based diffs so that history
    /// is preserved and change auditing remains possible.
    public func apply(diff: StateDiff) {
        lock.lock()
        defer { lock.unlock() }
        history.append(current)
        if history.count > maxHistory {
            history.removeFirst()
        }
        current = StateUpdater.apply(diff: diff, to: current)
    }

    /// Replace the model entirely from a fresh ``WorldState`` observation.
    public func reset(from worldState: WorldState) {
        lock.lock()
        defer { lock.unlock() }
        history.append(current)
        if history.count > maxHistory {
            history.removeFirst()
        }
        current = WorldModelSnapshot(from: worldState)
    }

    /// Replaces the committed snapshot directly.
    ///
    /// This is reserved for reducer-driven state projection after events have
    /// already been committed to the append-only event store.
    public func replaceCommittedSnapshot(_ snapshot: WorldModelSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        history.append(current)
        if history.count > maxHistory {
            history.removeFirst()
        }
        current = snapshot
    }

    /// Returns the N most recent snapshots in chronological order (oldest first).
    public func recentHistory(limit: Int = 5) -> [WorldModelSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return Array(history.suffix(limit))
    }
}

/// An immutable snapshot of the world model at a point in time.
public struct WorldModelSnapshot: Sendable {
    public let timestamp: Date
    public let cycleCount: Int
    public let activeApplication: String?
    public let windowTitle: String?
    public let url: String?
    public let visibleElementCount: Int
    public let modalPresent: Bool
    public let repositoryRoot: String?
    public let activeBranch: String?
    public let isGitDirty: Bool
    public let openFileCount: Int
    public let buildSucceeded: Bool?
    public let failingTestCount: Int?
    public let planningStateID: String?
    public let observationHash: String?
    public let processNames: [String]
    public let knowledgeSignals: [String]
    public let notes: [String]
    public let lastSequenceNumber: Int

    public init(
        timestamp: Date = Date(),
        cycleCount: Int = 0,
        activeApplication: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        visibleElementCount: Int = 0,
        modalPresent: Bool = false,
        repositoryRoot: String? = nil,
        activeBranch: String? = nil,
        isGitDirty: Bool = false,
        openFileCount: Int = 0,
        buildSucceeded: Bool? = nil,
        failingTestCount: Int? = nil,
        planningStateID: String? = nil,
        observationHash: String? = nil,
        processNames: [String] = [],
        knowledgeSignals: [String] = [],
        notes: [String] = [],
        lastSequenceNumber: Int = -1
    ) {
        self.timestamp = timestamp
        self.cycleCount = cycleCount
        self.activeApplication = activeApplication
        self.windowTitle = windowTitle
        self.url = url
        self.visibleElementCount = visibleElementCount
        self.modalPresent = modalPresent
        self.repositoryRoot = repositoryRoot
        self.activeBranch = activeBranch
        self.isGitDirty = isGitDirty
        self.openFileCount = openFileCount
        self.buildSucceeded = buildSucceeded
        self.failingTestCount = failingTestCount
        self.planningStateID = planningStateID
        self.observationHash = observationHash
        self.processNames = processNames
        self.knowledgeSignals = knowledgeSignals
        self.notes = notes
        self.lastSequenceNumber = lastSequenceNumber
    }

    public init(from worldState: WorldState) {
        self.init(
            activeApplication: worldState.observation.app,
            windowTitle: worldState.observation.windowTitle,
            url: worldState.observation.url,
            visibleElementCount: worldState.observation.elements.count,
            modalPresent: worldState.planningState.modalClass != nil,
            repositoryRoot: worldState.repositorySnapshot?.workspaceRoot,
            activeBranch: worldState.repositorySnapshot?.activeBranch,
            isGitDirty: worldState.repositorySnapshot?.isGitDirty ?? false,
            openFileCount: worldState.repositorySnapshot?.files.count ?? 0,
            planningStateID: worldState.planningState.id.rawValue,
            observationHash: worldState.observationHash
        )
    }

    /// Returns a copy with the specified fields overridden.
    public func copy(
        activeApplication: String?? = nil,
        windowTitle: String?? = nil,
        url: String?? = nil,
        visibleElementCount: Int? = nil,
        modalPresent: Bool? = nil,
        repositoryRoot: String?? = nil,
        activeBranch: String?? = nil,
        isGitDirty: Bool? = nil,
        openFileCount: Int? = nil,
        buildSucceeded: Bool?? = nil,
        failingTestCount: Int?? = nil,
        planningStateID: String?? = nil,
        observationHash: String?? = nil,
        processNames: [String]? = nil,
        knowledgeSignals: [String]? = nil,
        notes: [String]? = nil,
        cycleCount: Int? = nil,
        lastSequenceNumber: Int? = nil
    ) -> WorldModelSnapshot {
        WorldModelSnapshot(
            timestamp: Date(),
            cycleCount: cycleCount ?? self.cycleCount,
            activeApplication: activeApplication ?? self.activeApplication,
            windowTitle: windowTitle ?? self.windowTitle,
            url: url ?? self.url,
            visibleElementCount: visibleElementCount ?? self.visibleElementCount,
            modalPresent: modalPresent ?? self.modalPresent,
            repositoryRoot: repositoryRoot ?? self.repositoryRoot,
            activeBranch: activeBranch ?? self.activeBranch,
            isGitDirty: isGitDirty ?? self.isGitDirty,
            openFileCount: openFileCount ?? self.openFileCount,
            buildSucceeded: buildSucceeded ?? self.buildSucceeded,
            failingTestCount: failingTestCount ?? self.failingTestCount,
            planningStateID: planningStateID ?? self.planningStateID,
            observationHash: observationHash ?? self.observationHash,
            processNames: processNames ?? self.processNames,
            knowledgeSignals: knowledgeSignals ?? self.knowledgeSignals,
            notes: notes ?? self.notes,
            lastSequenceNumber: lastSequenceNumber ?? self.lastSequenceNumber
        )
    }
}
