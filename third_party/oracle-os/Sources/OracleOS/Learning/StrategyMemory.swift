import Foundation

public final class StrategyMemory {

    private var controls: [String: KnownControl] = [:]
    private var failures: [FailurePattern] = []
    private var strategies: [StrategyRecord] = []
    private var protectedOperationCounts: [String: Int] = [:]
    private var approvalCounts: [String: Int] = [:]
    private var codeMemory = CodeMemoryStore()

    public init() {}

    public func recordControl(_ control: KnownControl) {
        if let existing = controls[control.key] {
            controls[control.key] = KnownControl(
                key: control.key,
                app: control.app,
                label: control.label ?? existing.label,
                role: control.role ?? existing.role,
                elementID: control.elementID ?? existing.elementID,
                successCount: existing.successCount + control.successCount,
                lastUsed: control.lastUsed
            )
        } else {
            controls[control.key] = control
        }
    }

    public func getControl(key: String) -> KnownControl? {
        controls[key]
    }

    public func preferredKnownControl(label: String, app: String) -> KnownControl? {
        let lowered = label.lowercased()
        return controls.values
            .filter { $0.app == app && $0.label?.lowercased() == lowered }
            .sorted { lhs, rhs in
                if lhs.successCount == rhs.successCount {
                    return lhs.lastUsed > rhs.lastUsed
                }
                return lhs.successCount > rhs.successCount
            }
            .first
    }

    public func recordFailure(_ failure: FailurePattern) {
        failures.append(failure)
    }

    public func recordStrategy(_ record: StrategyRecord) {
        strategies.append(record)
    }

    public func controlsForApp(_ app: String) -> [KnownControl] {
        controls.values.filter { $0.app == app }
    }

    public func failuresForApp(_ app: String) -> [FailurePattern] {
        failures.filter { $0.app == app }
    }

    public func strategiesForApp(_ app: String) -> [StrategyRecord] {
        strategies.filter { $0.app == app }
    }

    public func recordProtectedOperation(app: String, operation: String) {
        protectedOperationCounts["\(app)|\(operation)", default: 0] += 1
    }

    public func recordApproval(app: String, operation: String) {
        approvalCounts["\(app)|\(operation)", default: 0] += 1
    }

    public func protectedOperationCount(app: String, operation: String) -> Int {
        protectedOperationCounts["\(app)|\(operation)", default: 0]
    }

    public func approvalCount(app: String, operation: String) -> Int {
        approvalCounts["\(app)|\(operation)", default: 0]
    }

    public func rankingBias(label: String?, app: String?) -> Double {
        guard let label, let app else { return 0 }
        let lowered = label.lowercased()
        guard let control = controls.values.first(where: {
            $0.app == app && $0.label?.lowercased() == lowered
        }) else {
            return 0
        }

        let failureCount = failures.filter {
            $0.app == app && $0.action.lowercased().contains(lowered)
        }.count
        let total = control.successCount + failureCount
        guard control.successCount >= 3, total > 0 else {
            return 0
        }

        let failureRate = Double(failureCount) / Double(total)
        guard failureRate <= 0.25 else {
            return 0
        }

        return min(log(Double(control.successCount) + 1) * 0.05, 0.15)
    }

    public func preferredRecoveryStrategy(app: String) -> String? {
        strategies
            .filter { $0.app == app && $0.success }
            .sorted { $0.timestamp > $1.timestamp }
            .first?
            .strategy
    }

    public func latestSuccessfulStrategy(app: String) -> StrategyRecord? {
        strategies
            .filter { $0.app == app && $0.success }
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    public func recordCodeError(_ pattern: ErrorPattern) {
        codeMemory.errorPatterns[pattern.signature] = pattern
    }

    public func recordFixPattern(_ pattern: FixPattern, success: Bool) {
        let key = [
            pattern.errorSignature,
            pattern.workspaceRelativePath ?? "none",
            pattern.commandCategory,
        ].joined(separator: "|")
        let existing = codeMemory.fixPatterns[key]
        codeMemory.fixPatterns[key] = FixPattern(
            errorSignature: pattern.errorSignature,
            workspaceRelativePath: pattern.workspaceRelativePath ?? existing?.workspaceRelativePath,
            commandCategory: pattern.commandCategory,
            successCount: (existing?.successCount ?? 0) + (success ? 1 : 0),
            failureCount: (existing?.failureCount ?? 0) + (success ? 0 : 1),
            lastAppliedAt: pattern.lastAppliedAt
        )
    }

    public func recordCommandResult(category: String, workspaceRoot: String, success: Bool) {
        let key = "\(workspaceRoot)|\(category)"
        if success {
            codeMemory.commandSuccesses[key, default: 0] += 1
        } else {
            codeMemory.commandFailures[key, default: 0] += 1
        }
    }

    public func preferredFixPath(errorSignature: String) -> String? {
        codeMemory.fixPatterns.values
            .filter { $0.errorSignature == errorSignature && $0.successCount >= 3 && $0.failureRate <= 0.25 }
            .sorted { lhs, rhs in
                if lhs.successCount == rhs.successCount {
                    return lhs.lastAppliedAt > rhs.lastAppliedAt
                }
                return lhs.successCount > rhs.successCount
            }
            .first?
            .workspaceRelativePath
    }

    public func fixPatterns(for errorSignature: String) -> [FixPattern] {
        codeMemory.fixPatterns.values
            .filter { $0.errorSignature == errorSignature }
    }

    public func commandBias(category: String, workspaceRoot: String) -> Double {
        let key = "\(workspaceRoot)|\(category)"
        let successes = codeMemory.commandSuccesses[key, default: 0]
        let failures = codeMemory.commandFailures[key, default: 0]
        let total = successes + failures
        guard successes >= 3, total > 0 else { return 0 }
        let failureRate = Double(failures) / Double(total)
        guard failureRate <= 0.25 else { return 0 }
        return min(log(Double(successes) + 1) * 0.05, 0.15)
    }

    public func commandSuccessCount(category: String, workspaceRoot: String) -> Int {
        codeMemory.commandSuccesses["\(workspaceRoot)|\(category)", default: 0]
    }

    public func commandFailureCount(category: String, workspaceRoot: String) -> Int {
        codeMemory.commandFailures["\(workspaceRoot)|\(category)", default: 0]
    }
}


public struct CodeMemoryStore: Sendable {
    public var errorPatterns: [String: ErrorPattern]
    public var fixPatterns: [String: FixPattern]
    public var commandSuccesses: [String: Int]
    public var commandFailures: [String: Int]

    public init(
        errorPatterns: [String: ErrorPattern] = [:],
        fixPatterns: [String: FixPattern] = [:],
        commandSuccesses: [String: Int] = [:],
        commandFailures: [String: Int] = [:]
    ) {
        self.errorPatterns = errorPatterns
        self.fixPatterns = fixPatterns
        self.commandSuccesses = commandSuccesses
        self.commandFailures = commandFailures
    }
}
