import Foundation

public struct ActionContract: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let agentKind: AgentKind
    public let domain: String
    public let skillName: String
    public let targetRole: String?
    public let targetLabel: String?
    public let locatorStrategy: String
    public let workspaceRelativePath: String?
    public let commandCategory: String?
    public let plannerFamily: String?

    public init(
        id: String,
        agentKind: AgentKind = .os,
        domain: String? = nil,
        skillName: String,
        targetRole: String?,
        targetLabel: String?,
        locatorStrategy: String,
        workspaceRelativePath: String? = nil,
        commandCategory: String? = nil,
        plannerFamily: String? = nil
    ) {
        self.id = id
        self.agentKind = agentKind
        self.domain = domain ?? (agentKind == .code ? "code" : "os")
        self.skillName = skillName
        self.targetRole = targetRole
        self.targetLabel = targetLabel
        self.locatorStrategy = locatorStrategy
        self.workspaceRelativePath = workspaceRelativePath
        self.commandCategory = commandCategory
        self.plannerFamily = plannerFamily
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "agent_kind": agentKind.rawValue,
            "domain": domain,
            "skill_name": skillName,
            "locator_strategy": locatorStrategy,
        ]
        if let targetRole {
            result["target_role"] = targetRole
        }
        if let targetLabel {
            result["target_label"] = targetLabel
        }
        if let workspaceRelativePath {
            result["workspace_relative_path"] = workspaceRelativePath
        }
        if let commandCategory {
            result["command_category"] = commandCategory
        }
        if let plannerFamily {
            result["planner_family"] = plannerFamily
        }
        return result
    }

    public static func from(
        intent: ActionIntent,
        method: String?,
        selectedElementLabel: String?,
        plannerFamily: String? = nil
    ) -> ActionContract {
        let locatorStrategy = method ?? inferredLocatorStrategy(for: intent)
        let targetLabel = selectedElementLabel ?? intent.targetQuery ?? intent.elementID
        let contractID = [
            intent.agentKind.rawValue,
            intent.action,
            intent.role ?? "none",
            targetLabel ?? "none",
            intent.workspaceRelativePath ?? "none",
            intent.commandCategory ?? "none",
            locatorStrategy,
        ].joined(separator: "|")

        return ActionContract(
            id: contractID,
            agentKind: intent.agentKind,
            skillName: intent.action,
            targetRole: intent.role,
            targetLabel: targetLabel,
            locatorStrategy: locatorStrategy,
            workspaceRelativePath: intent.workspaceRelativePath,
            commandCategory: intent.commandCategory,
            plannerFamily: plannerFamily
        )
    }

    private static func inferredLocatorStrategy(for intent: ActionIntent) -> String {
        if intent.x != nil || intent.y != nil {
            return "coordinates"
        }
        if intent.domID != nil {
            return "dom-id"
        }
        if intent.query != nil {
            return "query"
        }
        return "direct"
    }
}
