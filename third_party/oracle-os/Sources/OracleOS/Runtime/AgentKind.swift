import Foundation

public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case os
    case code
    case mixed
}

public enum PlannerFamily: String, Codable, Sendable, CaseIterable {
    case os
    case code
    case mixed
}

public enum TaskStepPhase: String, Codable, Sendable, CaseIterable {
    case operatingSystem
    case engineering
    case handoff
}
