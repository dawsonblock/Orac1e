import Foundation
public struct PlanTrace: Sendable, Codable {
    public let intentID: UUID; public let commandID: CommandID; public let planningSteps: [String]; public let timestamp: Date
    public init(intentID: UUID, commandID: CommandID, planningSteps: [String], timestamp: Date = Date()) {
        self.intentID = intentID; self.commandID = commandID; self.planningSteps = planningSteps; self.timestamp = timestamp }
}
