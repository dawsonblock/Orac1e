import Foundation

public struct LoopBudget: Sendable {
    public let maxSteps: Int
    public let maxRecoveries: Int
    public let maxConsecutiveExplorationSteps: Int
    public let maxPatchIterations: Int
    public let maxBuildAttempts: Int
    public let maxTestAttempts: Int
    public let maxConsecutiveStalls: Int

    public init(
        maxSteps: Int = 25,
        maxRecoveries: Int = 5,
        maxConsecutiveExplorationSteps: Int = 3,
        maxPatchIterations: Int = 5,
        maxBuildAttempts: Int = 5,
        maxTestAttempts: Int = 5,
        maxConsecutiveStalls: Int = 3
    ) {
        self.maxSteps = maxSteps
        self.maxRecoveries = maxRecoveries
        self.maxConsecutiveExplorationSteps = maxConsecutiveExplorationSteps
        self.maxPatchIterations = maxPatchIterations
        self.maxBuildAttempts = maxBuildAttempts
        self.maxTestAttempts = maxTestAttempts
        self.maxConsecutiveStalls = maxConsecutiveStalls
    }
}

public struct LoopBudgetState: Sendable, Equatable {
    public private(set) var recoveries: Int
    public private(set) var consecutiveExplorationSteps: Int
    public private(set) var patchIterations: Int
    public private(set) var buildAttempts: Int
    public private(set) var testAttempts: Int

    public init(
        recoveries: Int = 0,
        consecutiveExplorationSteps: Int = 0,
        patchIterations: Int = 0,
        buildAttempts: Int = 0,
        testAttempts: Int = 0
    ) {
        self.recoveries = recoveries
        self.consecutiveExplorationSteps = consecutiveExplorationSteps
        self.patchIterations = patchIterations
        self.buildAttempts = buildAttempts
        self.testAttempts = testAttempts
    }

    public mutating func registerPlannerSource(
        _ source: PlannerSource,
        budget: LoopBudget
    ) -> LoopTerminationReason? {
        if source == .exploration {
            consecutiveExplorationSteps += 1
            if consecutiveExplorationSteps > budget.maxConsecutiveExplorationSteps {
                return .explorationBudgetExceeded
            }
        } else {
            consecutiveExplorationSteps = 0
        }

        return nil
    }

    public mutating func registerExecution(
        intent: ActionIntent,
        budget: LoopBudget
    ) -> LoopTerminationReason? {
        switch intent.commandCategory {
        case CodeCommandCategory.generatePatch.rawValue,
             CodeCommandCategory.editFile.rawValue,
             CodeCommandCategory.writeFile.rawValue:
            patchIterations += 1
        case CodeCommandCategory.build.rawValue:
            buildAttempts += 1
        case CodeCommandCategory.test.rawValue:
            testAttempts += 1
        default:
            break
        }

        if patchIterations > budget.maxPatchIterations
            || buildAttempts > budget.maxBuildAttempts
            || testAttempts > budget.maxTestAttempts
        {
            return .lowConfidenceRepeatedFailure
        }

        return nil
    }

    public func canRecover(under budget: LoopBudget) -> Bool {
        recoveries < budget.maxRecoveries
    }

    public mutating func registerRecoveryAttempt() {
        recoveries += 1
    }
}
