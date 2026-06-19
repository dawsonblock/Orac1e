import Foundation

public struct Goal: Codable, Sendable, Equatable {
    public let description: String
    public let targetApp: String?
    public let targetDomain: String?
    public let targetTaskPhase: String?
    public let workspaceRoot: String?
    public let preferredAgentKind: AgentKind?
    public let experimentCandidates: [CandidatePatch]?

    public init(
        description: String,
        targetApp: String? = nil,
        targetDomain: String? = nil,
        targetTaskPhase: String? = nil,
        workspaceRoot: String? = nil,
        preferredAgentKind: AgentKind? = nil,
        experimentCandidates: [CandidatePatch]? = nil
    ) {
        self.description = description
        self.targetApp = targetApp
        self.targetDomain = targetDomain
        self.targetTaskPhase = targetTaskPhase
        self.workspaceRoot = workspaceRoot
        self.preferredAgentKind = preferredAgentKind
        self.experimentCandidates = experimentCandidates
    }

    public static func interpret(_ description: String) -> Goal {
        let lowercased = description.lowercased()
        let targetApp: String?
        if lowercased.contains("gmail") || lowercased.contains("browser") || lowercased.contains("chrome") {
            targetApp = "Google Chrome"
        } else if lowercased.contains("finder") {
            targetApp = "Finder"
        } else {
            targetApp = nil
        }

        let targetDomain: String?
        if lowercased.contains("gmail") {
            targetDomain = "mail.google.com"
        } else if lowercased.contains("slack") {
            targetDomain = "slack.com"
        } else {
            targetDomain = nil
        }

        let targetTaskPhase: String?
        if lowercased.contains("compose") {
            targetTaskPhase = "compose"
        } else if lowercased.contains("inbox") {
            targetTaskPhase = "browse"
        } else if lowercased.contains("save") {
            targetTaskPhase = "save"
        } else if lowercased.contains("rename") {
            targetTaskPhase = "rename"
        } else {
            targetTaskPhase = nil
        }

        return Goal(
            description: description,
            targetApp: targetApp,
            targetDomain: targetDomain,
            targetTaskPhase: targetTaskPhase
        )
    }

    public func matchScore(state: PlanningState) -> Double {
        var matched = 0.0
        var possible = 0.0

        if let targetApp = targetApp {
            possible += 1
            if state.appID == targetApp { matched += 1 }
        }
        if let targetDomain = targetDomain {
            possible += 1
            if state.domain == targetDomain { matched += 1 }
        }
        if let targetTaskPhase = targetTaskPhase {
            possible += 1
            if state.taskPhase == targetTaskPhase { matched += 1 }
        }

        guard possible > 0 else { return 0 }
        return matched / possible
    }
}

