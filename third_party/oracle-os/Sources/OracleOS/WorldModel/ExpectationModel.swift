import Foundation

/// Expected environment state after an action or at a checkpoint.
///
/// Used by `EnvironmentMonitor` to detect discrepancies between the
/// current world state and what the runtime believes should be true.
public struct ExpectationModel: Sendable {
    public let expectedApp: String?
    public let expectedElements: [String]
    public let expectedURL: String?
    public let expectedWindowTitle: String?

    public init(
        expectedApp: String? = nil,
        expectedElements: [String] = [],
        expectedURL: String? = nil,
        expectedWindowTitle: String? = nil
    ) {
        self.expectedApp = expectedApp
        self.expectedElements = expectedElements
        self.expectedURL = expectedURL
        self.expectedWindowTitle = expectedWindowTitle
    }
}
