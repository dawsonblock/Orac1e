// StateMemoryIndex.swift — Searchable index of compressed state signatures.
//
// Compressed states (produced by ``StateAbstractionEngine``) are stored
// with their associated action history and success rates. The planner
// queries the index to reuse previously successful strategies when it
// encounters a familiar state.

import Foundation

// MARK: - State signature

/// A lightweight fingerprint of a ``CompressedUIState`` used as an
/// index key. Two states with the same signature are considered
/// semantically equivalent for planning purposes.
public struct StateSignature: Sendable, Codable, Hashable {
    public let app: String?
    public let windowTitle: String?
    public let elementFingerprint: String

    public init(from state: CompressedUIState) {
        self.app = state.app
        self.windowTitle = state.windowTitle
        let parts = state.elements.map { "\($0.kind.rawValue)|\($0.label)" }
        self.elementFingerprint = parts.sorted().joined(separator: ";")
    }

    public init(app: String?, windowTitle: String?, elementFingerprint: String) {
        self.app = app
        self.windowTitle = windowTitle
        self.elementFingerprint = elementFingerprint
    }
}

// MARK: - State memory entry

/// A record associating a state signature with the actions that have
/// been attempted from that state and their outcomes.
public struct StateMemoryEntry: Sendable, Codable {
    public let signature: StateSignature
    /// Action name → (attempts, successes).
    public var actionStats: [String: ActionStats]
    /// Timestamp of the most recent observation of this state.
    public var lastSeen: TimeInterval

    public init(
        signature: StateSignature,
        actionStats: [String: ActionStats] = [:],
        lastSeen: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.signature = signature
        self.actionStats = actionStats
        self.lastSeen = lastSeen
    }

    /// Return the best action (highest success rate with at least one attempt).
    public var bestAction: String? {
        actionStats
            .filter { $0.value.attempts > 0 }
            .max(by: { $0.value.successRate < $1.value.successRate })?
            .key
    }
}

/// Aggregated success/failure counts for one action in one state.
public struct ActionStats: Sendable, Codable {
    private enum CodingKeys: String, CodingKey {
        case actionName
        case attempts
        case successes
    }

    /// The action name this statistic tracks.
    public let actionName: String
    public var attempts: Int
    public var successes: Int

    public var successRate: Double {
        guard attempts > 0 else { return 0 }
        return Double(successes) / Double(attempts)
    }

    public init(actionName: String = "", attempts: Int = 0, successes: Int = 0) {
        self.actionName = actionName
        self.attempts = attempts
        self.successes = successes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // For backward compatibility, default `actionName` when missing.
        self.actionName = try container.decodeIfPresent(String.self, forKey: .actionName) ?? ""
        self.attempts = try container.decode(Int.self, forKey: .attempts)
        self.successes = try container.decode(Int.self, forKey: .successes)
    }
}

// MARK: - State memory index

/// In-memory index of compressed state signatures with associated
/// action statistics. The planner queries this to reuse known-good
/// strategies.
///
/// Thread-safety: All reads and writes are serialised through an
/// internal lock. Safe to call from any thread or isolation domain.
public final class StateMemoryIndex: @unchecked Sendable {
    private var entries: [StateSignature: StateMemoryEntry]
    private let maxEntries: Int
    private let lock = NSLock()

    public init(maxEntries: Int = 5_000) {
        self.entries = [:]
        self.maxEntries = maxEntries
    }

    // MARK: - Query

    /// Look up the memory entry for a compressed UI state.
    public func lookup(_ state: CompressedUIState) -> StateMemoryEntry? {
        let sig = StateSignature(from: state)
        lock.lock()
        defer { lock.unlock() }
        return entries[sig]
    }

    /// Return the best known action for the given state, if any.
    public func bestAction(for state: CompressedUIState) -> String? {
        lookup(state)?.bestAction
    }

    /// Return actions attempted from this state, sorted by historical
    /// success rate (best first). This is the primary API for
    /// memory-driven action selection.
    public func likelyActions(for state: CompressedUIState) -> [ActionStats] {
        guard let entry = lookup(state) else { return [] }
        return entry.actionStats.values
            .filter { $0.attempts > 0 }
            .sorted { $0.successRate > $1.successRate }
    }

    /// Number of stored state signatures.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    // MARK: - Record

    /// Record the outcome of an action in a given compressed state.
    public func record(
        state: CompressedUIState,
        actionName: String,
        success: Bool
    ) {
        let sig = StateSignature(from: state)
        lock.lock()
        defer { lock.unlock() }
        var entry = entries[sig] ?? StateMemoryEntry(signature: sig)
        var stats = entry.actionStats[actionName] ?? ActionStats(actionName: actionName)
        stats.attempts += 1
        if success { stats.successes += 1 }
        entry.actionStats[actionName] = stats
        entry.lastSeen = Date().timeIntervalSince1970
        entries[sig] = entry
        evictIfNeeded()
    }

    // MARK: - Maintenance

    /// Remove the oldest entries when the index exceeds its capacity.
    /// Caller must hold `lock`.
    private func evictIfNeeded() {
        guard entries.count > maxEntries else { return }
        let sorted = entries.sorted { $0.value.lastSeen < $1.value.lastSeen }
        let toRemove = entries.count - maxEntries
        for (key, _) in sorted.prefix(toRemove) {
            entries.removeValue(forKey: key)
        }
    }
}
