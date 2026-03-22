import Foundation

public enum ExpectedPostcondition: Sendable, Codable, Equatable {
    case activeApplication(String)
    case windowTitleContains(String)
    case urlContains(String)
    case fileExists(String)
    case fileContentsChanged(String)
    case buildSucceeded
    case testsCompleted
}

public struct ExecutionEvidence: Sendable, Codable, Equatable {
    public let observations: [ObservationPayload]
    public let artifacts: [ArtifactPayload]
    public let events: [EventEnvelope]
    public let expectedPostconditions: [ExpectedPostcondition]
    public let notes: [String]

    public init(
        observations: [ObservationPayload] = [],
        artifacts: [ArtifactPayload] = [],
        events: [EventEnvelope] = [],
        expectedPostconditions: [ExpectedPostcondition] = [],
        notes: [String] = []
    ) {
        self.observations = observations
        self.artifacts = artifacts
        self.events = events
        self.expectedPostconditions = expectedPostconditions
        self.notes = notes
    }

    public func withEvents(_ events: [EventEnvelope]) -> ExecutionEvidence {
        ExecutionEvidence(
            observations: observations,
            artifacts: artifacts,
            events: events,
            expectedPostconditions: expectedPostconditions,
            notes: notes
        )
    }
}
