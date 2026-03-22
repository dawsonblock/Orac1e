import Foundation

/// Validates that a command is safe to execute under current system policy.
/// Returns (safe: true, reason: "") if allowed, or (safe: false, reason: "") if blocked.
public struct SafetyValidator: Sendable {
    // Sensitive operations that require extra scrutiny
    private let sensitiveKinds: Set<String> = [
        "modifyFile", "launchApp", "openURL", "runBuild"
    ]
    
    // Protected applications that require approval
    private let protectedApps: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.passwords",
        "1Password",
        "Keychain Access"
    ]
    
    public init() {}
    
    /// Returns true if the command is safe to execute under current policy.
    public func isSafe(_ command: Command, state: WorldStateModel) -> (safe: Bool, reason: String) {
        let snapshot = state.snapshot
        
        // Check for dangerous command kinds
        if sensitiveKinds.contains(command.kind) {
            // Check if target app is protected
            if let app = snapshot.activeApplication, protectedApps.contains(app) {
                return (false, "Protected application: \(app) requires approval")
            }
            
            // Log sensitive operations
            logSafetyCheck(command: command, state: snapshot, result: .allowed)
        }
        
        // Check for potentially harmful patterns in command metadata
        let rationale = command.metadata.rationale
        if containsDangerousPattern(rationale) {
            return (false, "Command rationale contains potentially dangerous pattern")
        }
        
        // Check planning strategy - warn on unknown but allow extension
        let knownStrategies: Set<String> = ["reasoning", "workflow", "ledger", "constraint", "hybrid", "graph", "exploration"]
        let strategy = command.metadata.planningStrategy.lowercased()
        if !knownStrategies.contains(strategy) && !strategy.isEmpty {
            // Log warning for unknown strategy but don't block - allows system extensibility
            logSafetyCheck(command: command, state: snapshot, result: .warned)
        }
        
        return (true, "")
    }
    
    private func containsDangerousPattern(_ text: String) -> Bool {
        let dangerous = ["rm -rf", "delete all", "drop table", "format:", "sudo"]
        let lowercased = text.lowercased()
        return dangerous.contains { lowercased.contains($0) }
    }
    
    private func logSafetyCheck(command: Command, state: WorldModelSnapshot, result: SafetyResult) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] SafetyCheck: \(command.kind) - \(result) - app=\(state.activeApplication ?? "none")")
    }
}

enum SafetyResult: Sendable {
    case allowed
    case blocked
    case warned
}
