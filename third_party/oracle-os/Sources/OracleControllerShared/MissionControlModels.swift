import Foundation

public enum DashboardTone: String, Codable, Sendable, CaseIterable {
    case neutral
    case good
    case warning
    case danger
}

public struct DashboardKPI: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let value: String
    public let detail: String
    public let tone: DashboardTone

    public init(
        id: String,
        title: String,
        value: String,
        detail: String,
        tone: DashboardTone = .neutral
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.detail = detail
        self.tone = tone
    }
}

public struct DashboardSeriesPoint: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let value: Double
    public let detail: String?

    public init(id: String, label: String, value: Double, detail: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.detail = detail
    }
}

public struct DashboardSeries: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let tone: DashboardTone
    public let points: [DashboardSeriesPoint]

    public init(
        id: String,
        title: String,
        subtitle: String,
        tone: DashboardTone = .neutral,
        points: [DashboardSeriesPoint]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.points = points
    }
}

public enum AlertSeverity: String, Codable, Sendable, CaseIterable {
    case info
    case warning
    case critical
}

public struct AlertSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let message: String
    public let severity: AlertSeverity
    public let source: String

    public init(
        id: String,
        title: String,
        message: String,
        severity: AlertSeverity,
        source: String
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.source = source
    }
}

public struct MissionActivityEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let timestamp: Date
    public let tone: DashboardTone
    public let traceSessionID: String?
    public let traceStepID: Int?

    public init(
        id: String,
        title: String,
        subtitle: String,
        timestamp: Date,
        tone: DashboardTone = .neutral,
        traceSessionID: String? = nil,
        traceStepID: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
        self.tone = tone
        self.traceSessionID = traceSessionID
        self.traceStepID = traceStepID
    }
}

public enum ChatProviderState: String, Codable, Sendable, CaseIterable {
    case ready
    case setupRequired = "setup_required"
    case unavailable
}

public struct ChatProviderStatus: Codable, Sendable, Equatable {
    public let providerID: String
    public let displayName: String
    public let state: ChatProviderState
    public let configured: Bool
    public let available: Bool
    public let canStream: Bool
    public let command: String?
    public let detail: String

    public init(
        providerID: String,
        displayName: String,
        state: ChatProviderState,
        configured: Bool,
        available: Bool,
        canStream: Bool,
        command: String? = nil,
        detail: String
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.state = state
        self.configured = configured
        self.available = available
        self.canStream = canStream
        self.command = command
        self.detail = detail
    }
}

public enum ChatCitationKind: String, Codable, Sendable, CaseIterable {
    case trace
    case approval
    case recipe
    case health
    case diagnostics
    case section
}

public struct ChatCitation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let kind: ChatCitationKind
    public let targetID: String?
    public let targetSectionID: String?

    public init(
        id: String,
        title: String,
        summary: String,
        kind: ChatCitationKind,
        targetID: String? = nil,
        targetSectionID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.kind = kind
        self.targetID = targetID
        self.targetSectionID = targetSectionID
    }
}

public enum ChatActionDraftKind: String, Codable, Sendable, CaseIterable {
    case action
    case recipe
    case openSection = "open_section"
}

public struct ChatActionDraft: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: ChatActionDraftKind
    public let actionRequest: ActionRequest?
    public let recipeName: String?
    public let sectionID: String?

    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: ChatActionDraftKind,
        actionRequest: ActionRequest? = nil,
        recipeName: String? = nil,
        sectionID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.actionRequest = actionRequest
        self.recipeName = recipeName
        self.sectionID = sectionID
    }
}

public enum ChatMessageRole: String, Codable, Sendable, CaseIterable {
    case system
    case user
    case assistant
}

public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let role: ChatMessageRole
    public let content: String
    public let createdAt: Date
    public let isStreaming: Bool
    public let citations: [ChatCitation]
    public let draftActions: [ChatActionDraft]

    public init(
        id: String,
        role: ChatMessageRole,
        content: String,
        createdAt: Date = Date(),
        isStreaming: Bool = false,
        citations: [ChatCitation] = [],
        draftActions: [ChatActionDraft] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.citations = citations
        self.draftActions = draftActions
    }
}

public struct ChatConversation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let messages: [ChatMessage]

    public init(
        id: String,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

public struct MissionControlSnapshot: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let kpis: [DashboardKPI]
    public let latencySeries: DashboardSeries
    public let successSeries: DashboardSeries
    public let workflowSeries: DashboardSeries
    public let recentActivity: [MissionActivityEntry]
    public let alerts: [AlertSummary]
    public let approvals: [ApprovalRequestDocument]
    public let workflows: [ControllerWorkflowDiagnostics]
    public let experiments: [ControllerExperimentDiagnostics]
    public let traceSessions: [TraceSessionSummary]
    public let repositoryIndexes: [ControllerRepositoryIndexDiagnostics]
    public let health: HealthStatus
    public let snapshot: ControlSnapshot?
    public let host: ControllerHostDiagnostics?
    public let browser: ControllerBrowserDiagnostics?
    public let providerStatus: ChatProviderStatus
    public let recommendedPrompts: [String]

    public init(
        generatedAt: Date = Date(),
        kpis: [DashboardKPI],
        latencySeries: DashboardSeries,
        successSeries: DashboardSeries,
        workflowSeries: DashboardSeries,
        recentActivity: [MissionActivityEntry],
        alerts: [AlertSummary],
        approvals: [ApprovalRequestDocument],
        workflows: [ControllerWorkflowDiagnostics],
        experiments: [ControllerExperimentDiagnostics],
        traceSessions: [TraceSessionSummary],
        repositoryIndexes: [ControllerRepositoryIndexDiagnostics],
        health: HealthStatus,
        snapshot: ControlSnapshot?,
        host: ControllerHostDiagnostics?,
        browser: ControllerBrowserDiagnostics?,
        providerStatus: ChatProviderStatus,
        recommendedPrompts: [String]
    ) {
        self.generatedAt = generatedAt
        self.kpis = kpis
        self.latencySeries = latencySeries
        self.successSeries = successSeries
        self.workflowSeries = workflowSeries
        self.recentActivity = recentActivity
        self.alerts = alerts
        self.approvals = approvals
        self.workflows = workflows
        self.experiments = experiments
        self.traceSessions = traceSessions
        self.repositoryIndexes = repositoryIndexes
        self.health = health
        self.snapshot = snapshot
        self.host = host
        self.browser = browser
        self.providerStatus = providerStatus
        self.recommendedPrompts = recommendedPrompts
    }
}
