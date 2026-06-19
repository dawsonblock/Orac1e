import Foundation

public final class PolicyEngine: @unchecked Sendable {
    public static let shared = PolicyEngine()

    public var mode: PolicyMode

    /// Cache for policy decisions to avoid repeated evaluation
    private var decisionCache: [String: CachedDecision] = [:]
    private let cacheLock = NSLock()

    /// Cache TTL in seconds (default 5 minutes)
    private let cacheTTL: TimeInterval = 300

    /// Repeated-action guard: tracks consecutive occurrences of the same
    /// protected operation. After `maxConsecutiveProtectedOps` hits the action
    /// is blocked, preventing tight loops that hammer risky operations.
    private var lastProtectedOperation: ProtectedOperation? = nil
    private var consecutiveProtectedOpCount: Int = 0
    private let maxConsecutiveProtectedOps: Int = 3

    /// Cached decision with timestamp for TTL tracking
    private struct CachedDecision {
        let decision: PolicyDecision
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300
        }
    }

    public init(mode: PolicyMode? = nil) {
        self.mode = mode ?? Self.defaultMode()
    }

    /// Reset the repeated-action guard (call when world state changes).
    public func resetRepeatedActionGuard() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        lastProtectedOperation = nil
        consecutiveProtectedOpCount = 0
    }

    /// Clear the policy decision cache (call after hot-reload)
    public func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        decisionCache.removeAll()
        Log.info("PolicyEngine: Decision cache cleared")
    }

    /// Reload policies with immediate cache invalidation
    public func reloadPolicies(mode: PolicyMode? = nil) {
        if let mode = mode {
            self.mode = mode
        }
        clearCache()
    }

    public func evaluate(intent: ActionIntent) -> PolicyDecision {
        evaluate(
            intent: intent,
            context: PolicyEvaluationContext(
                surface: .mcp,
                toolName: nil,
                appName: intent.app,
                agentKind: intent.agentKind,
                workspaceRoot: intent.workspaceRoot,
                workspaceRelativePath: intent.workspaceRelativePath,
                commandCategory: intent.commandCategory
            )
        )
    }

    /// Canonical command-level policy validation used by VerifiedExecutor.
    public func validate(_ command: Command) throws -> PolicyDecision {
        // Keep shell execution rules and runner policy in sync.
        if case .shell(let spec) = command.payload, spec.executable != "/usr/bin/env" && spec.executable != "/usr/bin/git" {
            return PolicyDecision(
                allowed: false,
                riskLevel: .blocked,
                protectedOperation: .workspaceWrite,
                appProtectionProfile: .lowRiskAllowed,
                blockedByPolicy: true,
                surface: surface(from: command.metadata.source),
                policyMode: mode,
                requiresApproval: false,
                reason: "Executable '\(spec.executable)' is not in the allowed executable set"
            )
        }

        let intent = actionIntent(from: command)
        let context = PolicyEvaluationContext(
            surface: surface(from: command.metadata.source),
            toolName: command.kind,
            appName: intent.app,
            agentKind: intent.agentKind,
            workspaceRoot: intent.workspaceRoot,
            workspaceRelativePath: intent.workspaceRelativePath,
            commandCategory: intent.commandCategory
        )
        return evaluate(intent: intent, context: context)
    }

    private func actionIntent(from command: Command) -> ActionIntent {
        switch command.payload {
        case .shell(let spec):
            return ActionIntent.code(
                name: command.kind,
                command: spec,
                workspaceRelativePath: spec.workspaceRelativePath
            )
        case .ui(let action):
            return ActionIntent(
                agentKind: .os,
                app: action.app ?? "unknown",
                name: action.name,
                action: action.name,
                query: action.query,
                text: action.text,
                role: action.role,
                domID: action.domID,
                x: action.x,
                y: action.y,
                button: action.button,
                count: action.count,
                modifiers: action.modifiers,
                amount: action.amount,
                windowTitle: action.windowTitle,
                clear: action.clear,
                width: action.width,
                height: action.height,
                postconditions: []
            )
        case .code(let action):
            return ActionIntent(
                agentKind: .code,
                app: action.app ?? "Workspace",
                name: action.name,
                action: action.name,
                query: action.query,
                text: action.patch,
                workspaceRoot: action.workspacePath,
                workspaceRelativePath: action.filePath,
                codeCommand: nil,
                postconditions: []
            )
        }
    }

    private func surface(from source: String) -> RuntimeSurface {
        let lowered = source.lowercased()
        if lowered.contains("controller") { return .controller }
        if lowered.contains("recipe") { return .recipe }
        if lowered.contains("cli") { return .cli }
        return .mcp
    }

    public func evaluate(intent: ActionIntent, context: PolicyEvaluationContext) -> PolicyDecision {
        let appProtectionProfile = PolicyRules.appProtectionProfile(for: context.appName ?? intent.app)
        let classification = PolicyRules.classification(
            for: intent,
            context: context,
            appProtectionProfile: appProtectionProfile
        )
        let protectedOperation = classification.protectedOperation
        let riskLevel = classification.riskLevel

        // Repeated-action guard: block if the same protected operation fires
        // too many consecutive times without an intervening state change.
        if let op = protectedOperation, riskLevel != .blocked {
            cacheLock.lock()
            if lastProtectedOperation == op {
                consecutiveProtectedOpCount += 1
            } else {
                lastProtectedOperation = op
                consecutiveProtectedOpCount = 1
            }
            let tripped = consecutiveProtectedOpCount > maxConsecutiveProtectedOps
            cacheLock.unlock()

            if tripped {
                Log.warn("PolicyEngine: repeated-action guard tripped for \(op.rawValue) (\(consecutiveProtectedOpCount) consecutive)")
                return PolicyDecision(
                    allowed: false,
                    riskLevel: .blocked,
                    protectedOperation: op,
                    appProtectionProfile: appProtectionProfile,
                    blockedByPolicy: true,
                    surface: context.surface,
                    policyMode: mode,
                    requiresApproval: false,
                    reason: "Repeated-action guard: \(op.rawValue) has fired \(consecutiveProtectedOpCount) consecutive times without a state change"
                )
            }
        }

        let baseDecision = PolicyDecision(
            allowed: riskLevel == .low,
            riskLevel: riskLevel,
            protectedOperation: protectedOperation,
            appProtectionProfile: appProtectionProfile,
            blockedByPolicy: riskLevel == .blocked,
            surface: context.surface,
            policyMode: mode,
            requiresApproval: riskLevel == .risky,
            reason: classification.reason ?? defaultReason(for: riskLevel, protectedOperation: protectedOperation, mode: mode)
        )

        switch mode {
        case .open:
            if riskLevel == .blocked {
                return baseDecision.withReason(baseDecision.reason ?? "Action blocked by policy")
            }
            return PolicyDecision(
                allowed: true,
                riskLevel: riskLevel,
                protectedOperation: protectedOperation,
                appProtectionProfile: appProtectionProfile,
                blockedByPolicy: false,
                surface: context.surface,
                policyMode: mode,
                requiresApproval: false,
                reason: baseDecision.reason
            )

        case .confirmRisky:
            return baseDecision

        case .lockedDown:
            if riskLevel == .low {
                return PolicyDecision(
                    allowed: true,
                    riskLevel: riskLevel,
                    protectedOperation: protectedOperation,
                    appProtectionProfile: appProtectionProfile,
                    blockedByPolicy: false,
                    surface: context.surface,
                    policyMode: mode,
                    requiresApproval: false,
                    reason: nil
                )
            }
            return PolicyDecision(
                allowed: false,
                riskLevel: riskLevel,
                protectedOperation: protectedOperation,
                appProtectionProfile: appProtectionProfile,
                blockedByPolicy: true,
                surface: context.surface,
                policyMode: mode,
                requiresApproval: false,
                reason: "Action blocked by locked-down policy"
            )
        }
    }

    public static func defaultMode() -> PolicyMode {
        guard let raw = ProcessInfo.processInfo.environment["ORACLE_OS_POLICY_MODE"] else {
            return .confirmRisky
        }
        return PolicyMode(rawValue: raw) ?? .confirmRisky
    }

    private func defaultReason(
        for riskLevel: RiskLevel,
        protectedOperation: ProtectedOperation?,
        mode: PolicyMode
    ) -> String? {
        switch riskLevel {
        case .low:
            return nil
        case .risky:
            return "Action requires approval in \(mode.rawValue) mode"
        case .blocked:
            if let protectedOperation {
                return "Action blocked by policy: \(protectedOperation.rawValue)"
            }
            return "Action blocked by policy"
        }
    }
}
