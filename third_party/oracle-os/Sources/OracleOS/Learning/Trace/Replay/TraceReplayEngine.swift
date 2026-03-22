// TraceReplayEngine.swift — Deterministic replay of recorded execution traces.
//
// Every executed action is recorded as a ``ReplayStep``. The replay engine
// can reconstruct the sequence, compare expected versus actual outcomes,
// and surface divergences for debugging or regression analysis.

import Foundation

// MARK: - Replay step

/// A single recorded step in an execution trace, capturing enough
/// information for deterministic replay.
public struct ReplayStep: Sendable, Codable, Identifiable {
    public let id: String
    public let timestamp: TimeInterval
    public let preStateHash: String
    public let postStateHash: String
    public let actionName: String
    public let schemaKind: ActionSchemaKind?
    public let criticOutcome: CriticOutcome
    public let elapsedMs: Double
    public let notes: [String]

    public init(
        id: String = UUID().uuidString,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        preStateHash: String,
        postStateHash: String,
        actionName: String,
        schemaKind: ActionSchemaKind? = nil,
        criticOutcome: CriticOutcome,
        elapsedMs: Double = 0,
        notes: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.preStateHash = preStateHash
        self.postStateHash = postStateHash
        self.actionName = actionName
        self.schemaKind = schemaKind
        self.criticOutcome = criticOutcome
        self.elapsedMs = elapsedMs
        self.notes = notes
    }
}

// MARK: - Replay trace

/// An ordered collection of ``ReplayStep`` values representing one
/// complete execution session.
public struct ReplayTrace: Sendable, Codable, Identifiable {
    public let id: String
    public let taskID: String?
    public let steps: [ReplayStep]
    public let startedAt: TimeInterval
    public let finishedAt: TimeInterval

    public init(
        id: String = UUID().uuidString,
        taskID: String? = nil,
        steps: [ReplayStep],
        startedAt: TimeInterval = Date().timeIntervalSince1970,
        finishedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.taskID = taskID
        self.steps = steps
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    /// Total number of steps.
    public var stepCount: Int { steps.count }

    /// Number of steps classified as failures or unknown by the critic.
    public var failureCount: Int {
        steps.filter { $0.criticOutcome == .failure || $0.criticOutcome == .unknown }.count
    }

    /// Overall success rate across all steps.
    public var successRate: Double {
        guard !steps.isEmpty else { return 0 }
        let successes = steps.filter { $0.criticOutcome == .success }.count
        return Double(successes) / Double(steps.count)
    }
}

// MARK: - Divergence

/// Describes a point where a replay diverged from the expected trace.
public struct ReplayDivergence: Sendable, Codable {
    public let stepIndex: Int
    public let expectedPostHash: String
    public let actualPostHash: String
    public let actionName: String
    public let note: String

    public init(
        stepIndex: Int,
        expectedPostHash: String,
        actualPostHash: String,
        actionName: String,
        note: String = ""
    ) {
        self.stepIndex = stepIndex
        self.expectedPostHash = expectedPostHash
        self.actualPostHash = actualPostHash
        self.actionName = actionName
        self.note = note
    }
}

// MARK: - Replay engine

/// Compares two traces and identifies divergences.
///
/// Usage:
///
///     let engine = TraceReplayEngine()
///     let divergences = engine.compare(expected: recorded, actual: replayed)
///
public struct TraceReplayEngine: Sendable {
    public init() {}

    /// Compare an expected trace against an actual (replayed) trace and
    /// return all points of divergence.
    public func compare(
        expected: ReplayTrace,
        actual: ReplayTrace
    ) -> [ReplayDivergence] {
        var divergences: [ReplayDivergence] = []
        let count = min(expected.steps.count, actual.steps.count)

        for i in 0..<count {
            let exp = expected.steps[i]
            let act = actual.steps[i]

            if exp.postStateHash != act.postStateHash {
                divergences.append(ReplayDivergence(
                    stepIndex: i,
                    expectedPostHash: exp.postStateHash,
                    actualPostHash: act.postStateHash,
                    actionName: exp.actionName,
                    note: exp.criticOutcome == act.criticOutcome
                        ? "state diverged but critic agrees"
                        : "state and critic diverged"
                ))
            }
        }

        if expected.steps.count != actual.steps.count {
            let longer = expected.steps.count > actual.steps.count ? "expected" : "actual"
            divergences.append(ReplayDivergence(
                stepIndex: count,
                expectedPostHash: "",
                actualPostHash: "",
                actionName: "length_mismatch",
                note: "\(longer) trace is longer (\(expected.steps.count) vs \(actual.steps.count))"
            ))
        }

        return divergences
    }

    /// Build a ``ReplayTrace`` from a ``CriticVerdict`` produced after
    /// each step in a live execution session. This is the recording side.
    public func buildStep(
        verdict: CriticVerdict,
        schemaKind: ActionSchemaKind? = nil,
        elapsedMs: Double = 0
    ) -> ReplayStep {
        ReplayStep(
            preStateHash: verdict.preStateHash,
            postStateHash: verdict.postStateHash,
            actionName: verdict.actionName,
            schemaKind: schemaKind,
            criticOutcome: verdict.outcome,
            elapsedMs: elapsedMs,
            notes: verdict.notes
        )
    }
}
