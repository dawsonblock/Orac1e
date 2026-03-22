import Foundation

public struct RecoveryPreparation: Sendable {
    public let strategyName: String
    public let resolution: SkillResolution
    public let notes: [String]

    public init(
        strategyName: String,
        resolution: SkillResolution,
        notes: [String] = []
    ) {
        self.strategyName = strategyName
        self.resolution = resolution
        self.notes = notes
    }
}

public struct RecoveryAttempt: Sendable {
    public let strategyName: String?
    public let preparation: RecoveryPreparation?
    public let message: String
    public let promptDiagnostics: PromptDiagnostics?

    public init(
        strategyName: String?,
        preparation: RecoveryPreparation?,
        message: String,
        promptDiagnostics: PromptDiagnostics? = nil
    ) {
        self.strategyName = strategyName
        self.preparation = preparation
        self.message = message
        self.promptDiagnostics = promptDiagnostics
    }
}

public enum RecoveryLayer: Int, Comparable, Sendable {
    case localRetry = 0
    case alternateTargeting
    case modeSwitch
    case interruptionHandling
    case skillFallback
    case replan

    public static func < (lhs: RecoveryLayer, rhs: RecoveryLayer) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

@MainActor
public protocol RecoveryStrategy {
    var name: String { get }
    var layer: RecoveryLayer { get }

    func prepare(
        failure: FailureClass,
        state: WorldState,
memoryStore: UnifiedMemoryStore
    ) async throws -> RecoveryPreparation?
}
