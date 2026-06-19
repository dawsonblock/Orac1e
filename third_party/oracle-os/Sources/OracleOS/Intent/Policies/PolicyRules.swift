import CryptoKit
import Foundation

public struct PolicyEvaluationContext: Sendable {
    public let surface: RuntimeSurface
    public let toolName: String?
    public let appName: String?
    public let agentKind: AgentKind?
    public let workspaceRoot: String?
    public let workspaceRelativePath: String?
    public let commandCategory: String?

    public init(
        surface: RuntimeSurface,
        toolName: String?,
        appName: String?,
        agentKind: AgentKind? = nil,
        workspaceRoot: String? = nil,
        workspaceRelativePath: String? = nil,
        commandCategory: String? = nil
    ) {
        self.surface = surface
        self.toolName = toolName
        self.appName = appName
        self.agentKind = agentKind
        self.workspaceRoot = workspaceRoot
        self.workspaceRelativePath = workspaceRelativePath
        self.commandCategory = commandCategory
    }
}

public enum PolicyRules {
    public static func appProtectionProfile(for appName: String?) -> AppProtectionProfile {
        let normalized = normalize(appName)

        if blockedApplicationPatterns.contains(where: { normalized.contains($0) }) {
            return .blocked
        }

        if confirmRiskyApplicationPatterns.contains(where: { normalized.contains($0) }) {
            return .confirmRisky
        }

        return .lowRiskAllowed
    }

    public static func classification(
        for intent: ActionIntent,
        context: PolicyEvaluationContext,
        appProtectionProfile: AppProtectionProfile
    ) -> (protectedOperation: ProtectedOperation?, riskLevel: RiskLevel, reason: String?) {
        if intent.agentKind == .code || context.agentKind == .code {
            return codeClassification(for: intent, context: context)
        }

        let protectedOperation = protectedOperation(
            for: intent,
            context: context,
            appProtectionProfile: appProtectionProfile
        )
        let riskLevel: RiskLevel = switch protectedOperation {
        case .credentialEntry, .settingsChange, .terminalControl, .clipboardExfiltration:
            .blocked
        case .send, .purchase, .delete, .uploadShare:
            .risky
        case .workspaceWrite, .gitPush, .destructiveVCS, .externalNetworkFetch:
            .risky
        case nil:
            .low
        }
        return (protectedOperation, riskLevel, nil)
    }

    public static func protectedOperation(
        for intent: ActionIntent,
        context: PolicyEvaluationContext,
        appProtectionProfile: AppProtectionProfile
    ) -> ProtectedOperation? {
        let action = intent.action.lowercased()
        let target = riskText(for: intent, toolName: context.toolName)
        let appName = normalize(context.appName ?? intent.app)

        if appProtectionProfile == .blocked, action != "focus" {
            if appName.contains("system settings") {
                return .settingsChange
            }
            return .terminalControl
        }

        if target.contains("password")
            || target.contains("passcode")
            || target.contains("otp")
            || target.contains("2fa")
            || target.contains("one-time code")
        {
            return .credentialEntry
        }

        if target.contains("send") || target.contains("submit") || target.contains("publish") {
            return .send
        }

        if target.contains("purchase")
            || target.contains("checkout")
            || target.contains("payment")
            || target.contains("buy")
        {
            return .purchase
        }

        if target.contains("delete")
            || target.contains("trash")
            || target.contains("remove")
            || target.contains("move to trash")
        {
            return .delete
        }

        if target.contains("upload")
            || target.contains("share")
            || target.contains("export")
            || target.contains("download")
        {
            return .uploadShare
        }

        if target.contains("clipboard")
            || (action == "press" && intent.query?.lowercased() == "c" && (intent.role?.lowercased().contains("cmd") == true))
        {
            return .clipboardExfiltration
        }

        if target.contains("system settings")
            || target.contains("privacy")
            || target.contains("security")
            || target.contains("permissions")
        {
            return .settingsChange
        }

        return nil
    }

    public static func actionFingerprint(intent: ActionIntent, toolName: String?) -> String {
        let seed = [
            toolName ?? "runtime",
            intent.agentKind.rawValue,
            intent.app,
            intent.action,
            intent.query ?? "",
            intent.role ?? "",
            intent.domID ?? "",
            intent.workspaceRoot ?? "",
            intent.workspaceRelativePath ?? "",
            intent.commandCategory ?? "",
            intent.commandSummary ?? "",
            coordinateFragment(x: intent.x, y: intent.y),
            redactedTextFragment(intent.text),
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func riskText(for intent: ActionIntent, toolName: String?) -> String {
        [
            toolName,
            intent.query,
            intent.domID,
            intent.role,
            redactText(intent.text),
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private static func coordinateFragment(x: Double?, y: Double?) -> String {
        guard let x, let y else { return "" }
        return "\(Int(x))x\(Int(y))"
    }

    private static func redactedTextFragment(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func redactText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }

        let lowered = text.lowercased()
        if lowered.contains("password")
            || lowered.contains("passcode")
            || lowered.contains("otp")
            || lowered.contains("2fa")
        {
            return "[redacted]"
        }

        return text
    }

    private static func normalize(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func codeClassification(
        for intent: ActionIntent,
        context: PolicyEvaluationContext
    ) -> (protectedOperation: ProtectedOperation?, riskLevel: RiskLevel, reason: String?) {
        guard let command = intent.codeCommand else {
            return (.workspaceWrite, .blocked, "Arbitrary shell execution is blocked")
        }

        guard let workspaceRoot = context.workspaceRoot ?? intent.workspaceRoot, !workspaceRoot.isEmpty else {
            return (.workspaceWrite, .blocked, "Workspace root is required for code actions")
        }

        if let relativePath = context.workspaceRelativePath ?? intent.workspaceRelativePath {
            if relativePath.hasPrefix("/") || relativePath.contains("../") {
                return (.workspaceWrite, .blocked, "Workspace path escapes the active workspace")
            }
        }

        if command.touchesNetwork {
            return (.externalNetworkFetch, .risky, "Remote network actions require approval")
        }

        switch command.category {
        case .indexRepository, .searchCode, .openFile, .parseBuildFailure, .parseTestFailure, .build, .test, .formatter, .linter, .gitStatus, .gitBranch, .gitCommit:
            return (nil, .low, nil)
        case .gitPush:
            let summary = command.summary.lowercased()
            if summary.contains("--force") || summary.contains("force") || summary.contains("delete") || summary.contains(" rebase ") || summary.contains(" merge ") {
                return (.destructiveVCS, .blocked, "Destructive VCS actions are blocked by policy")
            }
            return (.gitPush, .risky, "Git push requires approval")
        case .editFile, .writeFile, .generatePatch:
            let path = intent.workspaceRelativePath ?? command.workspaceRelativePath ?? ""
            if path.isEmpty {
                return (.workspaceWrite, .blocked, "Workspace write target is missing")
            }
            if isSensitiveWorkspacePath(path) {
                return (.workspaceWrite, .risky, "Sensitive workspace writes require approval")
            }
            if isSafeSourcePath(path) {
                return (nil, .low, nil)
            }
            return (.workspaceWrite, .risky, "Writes outside source/test paths require approval")
        }
    }

    private static func isSafeSourcePath(_ path: String) -> Bool {
        let normalized = normalize(path)
        return normalized.hasPrefix("sources/")
            || normalized.hasPrefix("tests/")
            || normalized == "package.swift"
            || normalized.hasPrefix("src/")
            || normalized.hasPrefix("lib/")
            || normalized.hasPrefix("docs/")
            || normalized.hasPrefix("documentation/")
    }

    private static func isSensitiveWorkspacePath(_ path: String) -> Bool {
        let normalized = normalize(path)
        let sensitiveFragments = [
            ".github/",
            ".circleci/",
            "ci/",
            "release",
            "deploy",
            "secret",
            "token",
            ".env",
            "package-lock.json",
            "pnpm-lock.yaml",
            "podfile.lock",
            // Executable build/deploy infrastructure
            "makefile",
            "dockerfile",
            ".gitconfig",
            ".ssh/",
            "fastlane/",
            "scripts/",
        ]
        return sensitiveFragments.contains(where: normalized.contains)
    }

    private static let blockedApplicationPatterns = [
        "terminal",
        "iterm",
        "hyper",
        "system settings",
        "keychain",
        "securityagent",
    ]

    private static let confirmRiskyApplicationPatterns = [
        "chrome",
        "safari",
        "firefox",
        "arc",
        "brave",
        "mail",
        "outlook",
        "slack",
        "messages",
        "finder",
        "notes",
        "textedit",
        "xcode",
        "visual studio code",
        "cursor",
    ]
}
