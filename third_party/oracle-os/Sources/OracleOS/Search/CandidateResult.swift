// CandidateResult.swift — The verified outcome of executing a single candidate.
//
// After the executor runs a candidate, the critic evaluates the result.
// This struct captures the full outcome so the ``ResultSelector`` can
// compare candidates deterministically.

import Foundation

/// The verified outcome of executing one ``Candidate``.
public struct CandidateResult: Sendable, Codable, Identifiable {
    public let id: String
    /// The candidate that was executed.
    public let candidate: Candidate
    /// Whether the candidate's postconditions were satisfied.
    public let success: Bool
    /// Composite score used for ranking (higher is better).
    public let score: Double
    /// The critic verdict from evaluation.
    public let criticOutcome: CriticOutcome
    /// Execution latency in milliseconds.
    public let elapsedMs: Double
    /// Optional notes from the critic.
    public let notes: [String]

    public init(
        id: String = UUID().uuidString,
        candidate: Candidate,
        success: Bool,
        score: Double,
        criticOutcome: CriticOutcome,
        elapsedMs: Double = 0,
        notes: [String] = []
    ) {
        self.id = id
        self.candidate = candidate
        self.success = success
        self.score = score
        self.criticOutcome = criticOutcome
        self.elapsedMs = elapsedMs
        self.notes = notes
    }
}
