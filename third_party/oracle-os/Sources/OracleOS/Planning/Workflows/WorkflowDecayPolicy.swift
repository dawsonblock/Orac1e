import Foundation

public struct WorkflowDecayPolicy: Sendable {
    public let maximumIdleDays: Int
    public let maximumValidationAgeDays: Int

    public init(
        maximumIdleDays: Int = 14,
        maximumValidationAgeDays: Int = 30
    ) {
        self.maximumIdleDays = maximumIdleDays
        self.maximumValidationAgeDays = maximumValidationAgeDays
    }

    public func isStale(_ plan: WorkflowPlan, now: Date = Date()) -> Bool {
        if let lastSucceededAt = plan.lastSucceededAt,
           daysBetween(lastSucceededAt, now) > maximumIdleDays {
            return true
        }
        if let lastValidatedAt = plan.lastValidatedAt,
           daysBetween(lastValidatedAt, now) > maximumValidationAgeDays {
            return true
        }
        return false
    }

    private func daysBetween(_ earlier: Date, _ later: Date) -> Int {
        Int(later.timeIntervalSince(earlier) / 86_400)
    }
}
