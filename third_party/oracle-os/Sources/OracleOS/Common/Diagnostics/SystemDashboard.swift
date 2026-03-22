import Foundation

public enum DashboardPanelKind: String, CaseIterable, Sendable {
    case agentState = "agent_state"
    case plannerDecision = "planner_decision"
    case recentActions = "recent_actions"
    case workflowReuse = "workflow_reuse"
    case memoryHits = "memory_hits"
    case recoveryEvents = "recovery_events"
    case systemLogs = "system_logs"
}

public struct DashboardPanel: Sendable {
    public let kind: DashboardPanelKind
    public let title: String
    public let entries: [DashboardEntry]

    public init(kind: DashboardPanelKind, title: String, entries: [DashboardEntry] = []) {
        self.kind = kind
        self.title = title
        self.entries = entries
    }
}

public struct DashboardEntry: Sendable {
    public let label: String
    public let value: String
    public let timestamp: Date?

    public init(label: String, value: String, timestamp: Date? = nil) {
        self.label = label
        self.value = value
        self.timestamp = timestamp
    }
}

public struct DashboardSnapshot: Sendable {
    public let panels: [DashboardPanel]
    public let generatedAt: Date

    public init(panels: [DashboardPanel], generatedAt: Date = Date()) {
        self.panels = panels
        self.generatedAt = generatedAt
    }
}

public final class SystemDashboard: @unchecked Sendable {
    private var recentActions: [(action: String, timestamp: Date)] = []
    private var recoveryEvents: [(failure: String, strategy: String?, timestamp: Date)] = []
    private var workflowReuses: [(workflowID: String, timestamp: Date)] = []
    private var memoryHits: [(query: String, hitCount: Int, timestamp: Date)] = []
    private var latestPlannerDecision: PlanDiagnostics?
    private let maxEntries: Int

    public init(maxEntries: Int = 100) {
        self.maxEntries = maxEntries
    }

    public func recordAction(_ action: String) {
        recentActions.append((action: action, timestamp: Date()))
        if recentActions.count > maxEntries {
            recentActions.removeFirst()
        }
    }

    public func recordRecovery(failure: String, strategy: String?) {
        recoveryEvents.append((failure: failure, strategy: strategy, timestamp: Date()))
        if recoveryEvents.count > maxEntries {
            recoveryEvents.removeFirst()
        }
    }

    public func recordWorkflowReuse(workflowID: String) {
        workflowReuses.append((workflowID: workflowID, timestamp: Date()))
        if workflowReuses.count > maxEntries {
            workflowReuses.removeFirst()
        }
    }

    public func recordMemoryHit(query: String, hitCount: Int) {
        memoryHits.append((query: query, hitCount: hitCount, timestamp: Date()))
        if memoryHits.count > maxEntries {
            memoryHits.removeFirst()
        }
    }

    public func recordPlannerDecision(_ diagnostics: PlanDiagnostics) {
        latestPlannerDecision = diagnostics
    }

    public func snapshot() -> DashboardSnapshot {
        DashboardSnapshot(panels: [
            plannerPanel(),
            recentActionsPanel(),
            workflowReusePanel(),
            memoryHitsPanel(),
            recoveryPanel(),
        ])
    }

    private func plannerPanel() -> DashboardPanel {
        var entries: [DashboardEntry] = []
        if let decision = latestPlannerDecision {
            entries.append(DashboardEntry(
                label: "Selected operators",
                value: decision.selectedOperatorNames.joined(separator: " → ")
            ))
            for candidate in decision.candidatePlans.prefix(3) {
                entries.append(DashboardEntry(
                    label: candidate.operatorNames.joined(separator: " → "),
                    value: "score: \(String(format: "%.2f", candidate.score))"
                ))
            }
            if let fallback = decision.fallbackReason {
                entries.append(DashboardEntry(label: "Fallback", value: fallback))
            }
        }
        return DashboardPanel(kind: .plannerDecision, title: "Planner Decision", entries: entries)
    }

    private func recentActionsPanel() -> DashboardPanel {
        let entries = recentActions.suffix(10).map { item in
            DashboardEntry(label: item.action, value: "", timestamp: item.timestamp)
        }
        return DashboardPanel(kind: .recentActions, title: "Recent Actions", entries: entries)
    }

    private func workflowReusePanel() -> DashboardPanel {
        let entries = workflowReuses.suffix(10).map { item in
            DashboardEntry(label: item.workflowID, value: "reused", timestamp: item.timestamp)
        }
        return DashboardPanel(kind: .workflowReuse, title: "Workflow Reuse", entries: entries)
    }

    private func memoryHitsPanel() -> DashboardPanel {
        let entries = memoryHits.suffix(10).map { item in
            DashboardEntry(label: item.query, value: "\(item.hitCount) hits", timestamp: item.timestamp)
        }
        return DashboardPanel(kind: .memoryHits, title: "Memory Hits", entries: entries)
    }

    private func recoveryPanel() -> DashboardPanel {
        let entries = recoveryEvents.suffix(10).map { item in
            DashboardEntry(
                label: item.failure,
                value: item.strategy ?? "no strategy",
                timestamp: item.timestamp
            )
        }
        return DashboardPanel(kind: .recoveryEvents, title: "Recovery Events", entries: entries)
    }
}
