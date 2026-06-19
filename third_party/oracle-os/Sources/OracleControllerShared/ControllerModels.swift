import Foundation

public struct ControllerSession: Codable, Sendable, Equatable {
    public let id: String
    public let startedAt: Date
    public let hostProcessID: Int32
    public let activeAppName: String?
    public let autoRefreshEnabled: Bool

    public init(
        id: String,
        startedAt: Date,
        hostProcessID: Int32,
        activeAppName: String? = nil,
        autoRefreshEnabled: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.hostProcessID = hostProcessID
        self.activeAppName = activeAppName
        self.autoRefreshEnabled = autoRefreshEnabled
    }
}

public struct ElementFrameSnapshot: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ElementSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let source: String
    public let role: String?
    public let label: String?
    public let value: String?
    public let frame: ElementFrameSnapshot?
    public let enabled: Bool
    public let visible: Bool
    public let focused: Bool
    public let confidence: Double

    public init(
        id: String,
        source: String,
        role: String? = nil,
        label: String? = nil,
        value: String? = nil,
        frame: ElementFrameSnapshot? = nil,
        enabled: Bool = true,
        visible: Bool = true,
        focused: Bool = false,
        confidence: Double = 1
    ) {
        self.id = id
        self.source = source
        self.role = role
        self.label = label
        self.value = value
        self.frame = frame
        self.enabled = enabled
        self.visible = visible
        self.focused = focused
        self.confidence = confidence
    }
}

public struct ObservationSnapshot: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let appName: String?
    public let windowTitle: String?
    public let url: String?
    public let focusedElementID: String?
    public let elements: [ElementSnapshot]

    public init(
        timestamp: Date,
        appName: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        focusedElementID: String? = nil,
        elements: [ElementSnapshot] = []
    ) {
        self.timestamp = timestamp
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.focusedElementID = focusedElementID
        self.elements = elements
    }
}

public struct ScreenshotFrame: Codable, Sendable, Equatable {
    public let base64PNG: String
    public let width: Int
    public let height: Int
    public let windowTitle: String?
    public let capturedAt: Date

    public init(
        base64PNG: String,
        width: Int,
        height: Int,
        windowTitle: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.base64PNG = base64PNG
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.capturedAt = capturedAt
    }
}

public struct ControlSnapshot: Codable, Sendable, Equatable {
    public let capturedAt: Date
    public let observation: ObservationSnapshot
    public let screenshot: ScreenshotFrame?

    public init(capturedAt: Date = Date(), observation: ObservationSnapshot, screenshot: ScreenshotFrame? = nil) {
        self.capturedAt = capturedAt
        self.observation = observation
        self.screenshot = screenshot
    }
}

public enum ActionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case focus
    case click
    case type
    case press
    case scroll
    case wait

    public var id: String { rawValue }
}

public struct ActionRequest: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: ActionKind
    public let appName: String?
    public let windowTitle: String?
    public let query: String?
    public let role: String?
    public let domID: String?
    public let text: String?
    public let clearExisting: Bool
    public let x: Double?
    public let y: Double?
    public let button: String?
    public let count: Int?
    public let key: String?
    public let modifiers: [String]?
    public let direction: String?
    public let amount: Int?
    public let waitCondition: String?
    public let waitValue: String?
    public let timeout: Double?
    public let interval: Double?
    public let approvalRequestID: String?

    public init(
        id: UUID = UUID(),
        kind: ActionKind,
        appName: String? = nil,
        windowTitle: String? = nil,
        query: String? = nil,
        role: String? = nil,
        domID: String? = nil,
        text: String? = nil,
        clearExisting: Bool = false,
        x: Double? = nil,
        y: Double? = nil,
        button: String? = nil,
        count: Int? = nil,
        key: String? = nil,
        modifiers: [String]? = nil,
        direction: String? = nil,
        amount: Int? = nil,
        waitCondition: String? = nil,
        waitValue: String? = nil,
        timeout: Double? = nil,
        interval: Double? = nil,
        approvalRequestID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.appName = appName
        self.windowTitle = windowTitle
        self.query = query
        self.role = role
        self.domID = domID
        self.text = text
        self.clearExisting = clearExisting
        self.x = x
        self.y = y
        self.button = button
        self.count = count
        self.key = key
        self.modifiers = modifiers
        self.direction = direction
        self.amount = amount
        self.waitCondition = waitCondition
        self.waitValue = waitValue
        self.timeout = timeout
        self.interval = interval
        self.approvalRequestID = approvalRequestID
    }

    public var displayTitle: String {
        switch kind {
        case .focus:
            return "Focus \(appName ?? "App")"
        case .click:
            return "Click \(query ?? domID ?? coordinateLabel)"
        case .type:
            return "Type into \(query ?? domID ?? "Focused Field")"
        case .press:
            return "Press \(key ?? "Key")"
        case .scroll:
            return "Scroll \(direction ?? "down")"
        case .wait:
            return "Wait for \(waitCondition ?? "Condition")"
        }
    }

    public var requiresConfirmation: Bool {
        let riskyTerms = [query, domID, text, key, waitValue]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return riskyTerms.contains("delete")
            || riskyTerms.contains("trash")
            || riskyTerms.contains("submit")
            || riskyTerms.contains("send")
            || riskyTerms.contains("purchase")
            || riskyTerms.contains("password")
    }

    private var coordinateLabel: String {
        if let x, let y {
            return "(\(Int(x)), \(Int(y)))"
        }
        return "Target"
    }
}

public struct ActionRunResult: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let request: ActionRequest
    public let success: Bool
    public let verified: Bool
    public let message: String?
    public let failureClass: String?
    public let method: String?
    public let elapsedMs: Double
    public let traceSessionID: String?
    public let traceStepID: Int?
    public let resultingObservation: ObservationSnapshot?
    public let approvalRequestID: String?
    public let approvalStatus: String?
    public let protectedOperation: String?
    public let appProtectionProfile: String?
    public let blockedByPolicy: Bool
    public let policyMode: String?
    public let agentKind: String?
    public let plannerFamily: String?
    public let commandCategory: String?
    public let commandSummary: String?
    public let workspaceRelativePath: String?
    public let buildResultSummary: String?
    public let testResultSummary: String?
    public let patchID: String?

    public init(
        id: UUID = UUID(),
        request: ActionRequest,
        success: Bool,
        verified: Bool,
        message: String? = nil,
        failureClass: String? = nil,
        method: String? = nil,
        elapsedMs: Double,
        traceSessionID: String? = nil,
        traceStepID: Int? = nil,
        resultingObservation: ObservationSnapshot? = nil,
        approvalRequestID: String? = nil,
        approvalStatus: String? = nil,
        protectedOperation: String? = nil,
        appProtectionProfile: String? = nil,
        blockedByPolicy: Bool = false,
        policyMode: String? = nil,
        agentKind: String? = nil,
        plannerFamily: String? = nil,
        commandCategory: String? = nil,
        commandSummary: String? = nil,
        workspaceRelativePath: String? = nil,
        buildResultSummary: String? = nil,
        testResultSummary: String? = nil,
        patchID: String? = nil
    ) {
        self.id = id
        self.request = request
        self.success = success
        self.verified = verified
        self.message = message
        self.failureClass = failureClass
        self.method = method
        self.elapsedMs = elapsedMs
        self.traceSessionID = traceSessionID
        self.traceStepID = traceStepID
        self.resultingObservation = resultingObservation
        self.approvalRequestID = approvalRequestID
        self.approvalStatus = approvalStatus
        self.protectedOperation = protectedOperation
        self.appProtectionProfile = appProtectionProfile
        self.blockedByPolicy = blockedByPolicy
        self.policyMode = policyMode
        self.agentKind = agentKind
        self.plannerFamily = plannerFamily
        self.commandCategory = commandCategory
        self.commandSummary = commandSummary
        self.workspaceRelativePath = workspaceRelativePath
        self.buildResultSummary = buildResultSummary
        self.testResultSummary = testResultSummary
        self.patchID = patchID
    }
}

public struct ApprovalRequestDocument: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let createdAt: Date
    public let surface: String
    public let toolName: String?
    public let appName: String?
    public let displayTitle: String
    public let reason: String
    public let riskLevel: String
    public let protectedOperation: String
    public let status: String
    public let appProtectionProfile: String

    public init(
        id: String,
        createdAt: Date,
        surface: String,
        toolName: String? = nil,
        appName: String? = nil,
        displayTitle: String,
        reason: String,
        riskLevel: String,
        protectedOperation: String,
        status: String,
        appProtectionProfile: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.surface = surface
        self.toolName = toolName
        self.appName = appName
        self.displayTitle = displayTitle
        self.reason = reason
        self.riskLevel = riskLevel
        self.protectedOperation = protectedOperation
        self.status = status
        self.appProtectionProfile = appProtectionProfile
    }
}

public struct PermissionStatus: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let granted: Bool
    public let detail: String?

    public init(id: String, title: String, granted: Bool, detail: String? = nil) {
        self.id = id
        self.title = title
        self.granted = granted
        self.detail = detail
    }
}



public struct ToolHealthStatus: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let capabilities: [String]
    public let baseURL: String
    public let invokePath: String
    public let healthPath: String
    public let riskLevel: String
    public let healthy: Bool
    public let detail: String?

    public init(
        id: String,
        name: String,
        kind: String,
        capabilities: [String],
        baseURL: String,
        invokePath: String,
        healthPath: String,
        riskLevel: String,
        healthy: Bool,
        detail: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.capabilities = capabilities
        self.baseURL = baseURL
        self.invokePath = invokePath
        self.healthPath = healthPath
        self.riskLevel = riskLevel
        self.healthy = healthy
        self.detail = detail
    }
}

public struct ToolRegistryHealth: Codable, Sendable, Equatable {
    public let rootPath: String
    public let toolCount: Int
    public let capabilities: [String]
    public let tools: [ToolHealthStatus]

    public init(
        rootPath: String,
        toolCount: Int,
        capabilities: [String],
        tools: [ToolHealthStatus]
    ) {
        self.rootPath = rootPath
        self.toolCount = toolCount
        self.capabilities = capabilities
        self.tools = tools
    }
}

public struct HealthStatus: Codable, Sendable, Equatable {
    public let updatedAt: Date
    public let runtimeVersion: String
    public let permissions: [PermissionStatus]
    public let claudeConfigured: Bool
    public let visionSidecarRunning: Bool
    public let visionSidecarVersion: String?
    public let visionModelPath: String?
    public let recipeDirectoryPath: String
    public let recipeCount: Int
    public let traceDirectoryPath: String
    public let applicationSupportPath: String
    public let approvalsDirectoryPath: String
    public let projectMemoryDirectoryPath: String
    public let experimentsDirectoryPath: String
    public let logsDirectoryPath: String
    public let graphDatabasePath: String
    public let approvalBrokerActive: Bool
    public let controllerConnected: Bool
    public let policyMode: String
    public let runningFromAppBundle: Bool
    public let bundledHostAvailable: Bool
    public let bundledVisionBootstrapAvailable: Bool
    public let visionInstallPath: String
    public let buildVersion: String
    public let buildNumber: String
    public let toolRegistry: ToolRegistryHealth?

    public init(
        updatedAt: Date = Date(),
        runtimeVersion: String,
        permissions: [PermissionStatus],
        claudeConfigured: Bool,
        visionSidecarRunning: Bool,
        visionSidecarVersion: String? = nil,
        visionModelPath: String? = nil,
        recipeDirectoryPath: String,
        recipeCount: Int,
        traceDirectoryPath: String,
        applicationSupportPath: String,
        approvalsDirectoryPath: String,
        projectMemoryDirectoryPath: String,
        experimentsDirectoryPath: String,
        logsDirectoryPath: String,
        graphDatabasePath: String,
        approvalBrokerActive: Bool,
        controllerConnected: Bool,
        policyMode: String,
        runningFromAppBundle: Bool,
        bundledHostAvailable: Bool,
        bundledVisionBootstrapAvailable: Bool,
        visionInstallPath: String,
        buildVersion: String,
        buildNumber: String,
        toolRegistry: ToolRegistryHealth? = nil
    ) {
        self.updatedAt = updatedAt
        self.runtimeVersion = runtimeVersion
        self.permissions = permissions
        self.claudeConfigured = claudeConfigured
        self.visionSidecarRunning = visionSidecarRunning
        self.visionSidecarVersion = visionSidecarVersion
        self.visionModelPath = visionModelPath
        self.recipeDirectoryPath = recipeDirectoryPath
        self.recipeCount = recipeCount
        self.traceDirectoryPath = traceDirectoryPath
        self.applicationSupportPath = applicationSupportPath
        self.approvalsDirectoryPath = approvalsDirectoryPath
        self.projectMemoryDirectoryPath = projectMemoryDirectoryPath
        self.experimentsDirectoryPath = experimentsDirectoryPath
        self.logsDirectoryPath = logsDirectoryPath
        self.graphDatabasePath = graphDatabasePath
        self.approvalBrokerActive = approvalBrokerActive
        self.controllerConnected = controllerConnected
        self.policyMode = policyMode
        self.runningFromAppBundle = runningFromAppBundle
        self.bundledHostAvailable = bundledHostAvailable
        self.bundledVisionBootstrapAvailable = bundledVisionBootstrapAvailable
        self.visionInstallPath = visionInstallPath
        self.buildVersion = buildVersion
        self.buildNumber = buildNumber
        self.toolRegistry = toolRegistry
    }
}

public struct ControllerGraphEdgeDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let actionContractID: String
    public let fromPlanningStateID: String
    public let toPlanningStateID: String
    public let agentKind: String
    public let domain: String
    public let workspaceRelativePath: String?
    public let commandCategory: String?
    public let plannerFamily: String?
    public let knowledgeTier: String
    public let attempts: Int
    public let successRate: Double
    public let averageLatencyMs: Double
    public let targetAmbiguityRate: Double
    public let rollingSuccessRate: Double
    public let recoveryTagged: Bool
    public let approvalRequired: Bool
    public let approvalOutcome: String?
    public let lastSuccessAt: Date?
    public let lastAttemptAt: Date?
    public let failureHistogram: [String: Int]
    public let promotionEligible: Bool

    public init(
        id: String,
        actionContractID: String,
        fromPlanningStateID: String,
        toPlanningStateID: String,
        agentKind: String,
        domain: String,
        workspaceRelativePath: String? = nil,
        commandCategory: String? = nil,
        plannerFamily: String? = nil,
        knowledgeTier: String,
        attempts: Int,
        successRate: Double,
        averageLatencyMs: Double,
        targetAmbiguityRate: Double,
        rollingSuccessRate: Double,
        recoveryTagged: Bool,
        approvalRequired: Bool,
        approvalOutcome: String? = nil,
        lastSuccessAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        failureHistogram: [String: Int] = [:],
        promotionEligible: Bool
    ) {
        self.id = id
        self.actionContractID = actionContractID
        self.fromPlanningStateID = fromPlanningStateID
        self.toPlanningStateID = toPlanningStateID
        self.agentKind = agentKind
        self.domain = domain
        self.workspaceRelativePath = workspaceRelativePath
        self.commandCategory = commandCategory
        self.plannerFamily = plannerFamily
        self.knowledgeTier = knowledgeTier
        self.attempts = attempts
        self.successRate = successRate
        self.averageLatencyMs = averageLatencyMs
        self.targetAmbiguityRate = targetAmbiguityRate
        self.rollingSuccessRate = rollingSuccessRate
        self.recoveryTagged = recoveryTagged
        self.approvalRequired = approvalRequired
        self.approvalOutcome = approvalOutcome
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.failureHistogram = failureHistogram
        self.promotionEligible = promotionEligible
    }
}

public struct ControllerGraphDiagnostics: Codable, Sendable, Equatable {
    public let stableEdges: [ControllerGraphEdgeDiagnostics]
    public let candidateEdges: [ControllerGraphEdgeDiagnostics]
    public let recoveryEdges: [ControllerGraphEdgeDiagnostics]
    public let promotionEligibleCount: Int
    public let promotionsFrozen: Bool
    public let globalSuccessRate: Double

    public init(
        stableEdges: [ControllerGraphEdgeDiagnostics],
        candidateEdges: [ControllerGraphEdgeDiagnostics],
        recoveryEdges: [ControllerGraphEdgeDiagnostics],
        promotionEligibleCount: Int,
        promotionsFrozen: Bool,
        globalSuccessRate: Double
    ) {
        self.stableEdges = stableEdges
        self.candidateEdges = candidateEdges
        self.recoveryEdges = recoveryEdges
        self.promotionEligibleCount = promotionEligibleCount
        self.promotionsFrozen = promotionsFrozen
        self.globalSuccessRate = globalSuccessRate
    }
}

extension ControllerGraphDiagnostics {
    public var recoveryStepCount: Int {
        recoveryEdges.count
    }
}

public struct ControllerWorkflowDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let goalPattern: String
    public let agentKind: String
    public let promotionStatus: String
    public let successRate: Double
    public let replayValidationSuccess: Double
    public let repeatedTraceSegmentCount: Int
    public let stepCount: Int
    public let parameterSlots: [String]
    public let sourceTraceRefs: [String]
    public let sourceGraphEdgeRefs: [String]
    public let stale: Bool

    public init(
        id: String,
        goalPattern: String,
        agentKind: String,
        promotionStatus: String,
        successRate: Double,
        replayValidationSuccess: Double,
        repeatedTraceSegmentCount: Int,
        stepCount: Int,
        parameterSlots: [String],
        sourceTraceRefs: [String],
        sourceGraphEdgeRefs: [String],
        stale: Bool
    ) {
        self.id = id
        self.goalPattern = goalPattern
        self.agentKind = agentKind
        self.promotionStatus = promotionStatus
        self.successRate = successRate
        self.replayValidationSuccess = replayValidationSuccess
        self.repeatedTraceSegmentCount = repeatedTraceSegmentCount
        self.stepCount = stepCount
        self.parameterSlots = parameterSlots
        self.sourceTraceRefs = sourceTraceRefs
        self.sourceGraphEdgeRefs = sourceGraphEdgeRefs
        self.stale = stale
    }
}

public struct ControllerExperimentCandidateDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let workspaceRelativePath: String
    public let hypothesis: String?
    public let selected: Bool
    public let succeeded: Bool
    public let architectureRiskScore: Double
    public let sandboxPath: String
    public let diffSummary: String
    public let buildSummary: String?
    public let testSummary: String?
    public let architectureFindings: [String]

    public init(
        id: String,
        title: String,
        summary: String,
        workspaceRelativePath: String,
        hypothesis: String? = nil,
        selected: Bool,
        succeeded: Bool,
        architectureRiskScore: Double,
        sandboxPath: String,
        diffSummary: String,
        buildSummary: String? = nil,
        testSummary: String? = nil,
        architectureFindings: [String]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.workspaceRelativePath = workspaceRelativePath
        self.hypothesis = hypothesis
        self.selected = selected
        self.succeeded = succeeded
        self.architectureRiskScore = architectureRiskScore
        self.sandboxPath = sandboxPath
        self.diffSummary = diffSummary
        self.buildSummary = buildSummary
        self.testSummary = testSummary
        self.architectureFindings = architectureFindings
    }
}

public struct ControllerExperimentDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let candidateCount: Int
    public let selectedCandidateID: String?
    public let winningSandboxPath: String?
    public let succeededCandidateCount: Int
    public let candidates: [ControllerExperimentCandidateDiagnostics]

    public init(
        id: String,
        candidateCount: Int,
        selectedCandidateID: String? = nil,
        winningSandboxPath: String? = nil,
        succeededCandidateCount: Int,
        candidates: [ControllerExperimentCandidateDiagnostics]
    ) {
        self.id = id
        self.candidateCount = candidateCount
        self.selectedCandidateID = selectedCandidateID
        self.winningSandboxPath = winningSandboxPath
        self.succeededCandidateCount = succeededCandidateCount
        self.candidates = candidates
    }
}

public struct ControllerRecoveryStrategyDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let attempts: Int
    public let successes: Int
    public let failures: Int
    public let failureHistogram: [String: Int]

    public init(
        id: String,
        attempts: Int,
        successes: Int,
        failures: Int,
        failureHistogram: [String: Int]
    ) {
        self.id = id
        self.attempts = attempts
        self.successes = successes
        self.failures = failures
        self.failureHistogram = failureHistogram
    }
}

public struct ControllerRecoveryDiagnostics: Codable, Sendable, Equatable {
    public let recoveryStepCount: Int
    public let strategies: [ControllerRecoveryStrategyDiagnostics]

    public init(recoveryStepCount: Int, strategies: [ControllerRecoveryStrategyDiagnostics]) {
        self.recoveryStepCount = recoveryStepCount
        self.strategies = strategies
    }
}

public struct ControllerProjectMemoryDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let kind: String
    public let knowledgeClass: String
    public let status: String
    public let path: String
    public let affectedModules: [String]
    public let evidenceRefs: [String]

    public init(
        id: String,
        title: String,
        summary: String,
        kind: String,
        knowledgeClass: String,
        status: String,
        path: String,
        affectedModules: [String],
        evidenceRefs: [String]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.kind = kind
        self.knowledgeClass = knowledgeClass
        self.status = status
        self.path = path
        self.affectedModules = affectedModules
        self.evidenceRefs = evidenceRefs
    }
}

public struct ControllerArchitectureFindingDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let severity: String
    public let affectedModules: [String]
    public let evidence: [String]
    public let riskScore: Double
    public let occurrences: Int
    public let governanceRuleID: String?

    public init(
        id: String,
        title: String,
        summary: String,
        severity: String,
        affectedModules: [String],
        evidence: [String],
        riskScore: Double,
        occurrences: Int,
        governanceRuleID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.severity = severity
        self.affectedModules = affectedModules
        self.evidence = evidence
        self.riskScore = riskScore
        self.occurrences = occurrences
        self.governanceRuleID = governanceRuleID
    }
}

public struct ControllerRepositoryIndexDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let workspaceRoot: String
    public let buildTool: String
    public let activeBranch: String?
    public let isGitDirty: Bool
    public let indexedAt: Date
    public let fileCount: Int
    public let symbolCount: Int
    public let dependencyCount: Int
    public let callEdgeCount: Int
    public let testEdgeCount: Int
    public let buildTargetCount: Int
    public let topSymbols: [String]
    public let buildTargets: [String]
    public let topTests: [String]

    public init(
        id: String,
        workspaceRoot: String,
        buildTool: String,
        activeBranch: String?,
        isGitDirty: Bool,
        indexedAt: Date,
        fileCount: Int,
        symbolCount: Int,
        dependencyCount: Int,
        callEdgeCount: Int,
        testEdgeCount: Int,
        buildTargetCount: Int,
        topSymbols: [String],
        buildTargets: [String],
        topTests: [String]
    ) {
        self.id = id
        self.workspaceRoot = workspaceRoot
        self.buildTool = buildTool
        self.activeBranch = activeBranch
        self.isGitDirty = isGitDirty
        self.indexedAt = indexedAt
        self.fileCount = fileCount
        self.symbolCount = symbolCount
        self.dependencyCount = dependencyCount
        self.callEdgeCount = callEdgeCount
        self.testEdgeCount = testEdgeCount
        self.buildTargetCount = buildTargetCount
        self.topSymbols = topSymbols
        self.buildTargets = buildTargets
        self.topTests = topTests
    }
}

public struct ControllerHostWindowDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let appName: String
    public let title: String?
    public let elementCount: Int
    public let focused: Bool

    public init(
        id: String,
        appName: String,
        title: String? = nil,
        elementCount: Int,
        focused: Bool
    ) {
        self.id = id
        self.appName = appName
        self.title = title
        self.elementCount = elementCount
        self.focused = focused
    }
}

public struct ControllerHostDiagnostics: Codable, Sendable, Equatable {
    public let snapshotID: String
    public let activeApplication: String?
    public let accessibilityGranted: Bool
    public let screenRecordingGranted: Bool
    public let windowCount: Int
    public let menuCount: Int
    public let dialogTitle: String?
    public let capturedWindowTitle: String?
    public let windows: [ControllerHostWindowDiagnostics]

    public init(
        snapshotID: String,
        activeApplication: String? = nil,
        accessibilityGranted: Bool,
        screenRecordingGranted: Bool,
        windowCount: Int,
        menuCount: Int,
        dialogTitle: String? = nil,
        capturedWindowTitle: String? = nil,
        windows: [ControllerHostWindowDiagnostics]
    ) {
        self.snapshotID = snapshotID
        self.activeApplication = activeApplication
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
        self.windowCount = windowCount
        self.menuCount = menuCount
        self.dialogTitle = dialogTitle
        self.capturedWindowTitle = capturedWindowTitle
        self.windows = windows
    }
}

public struct ControllerBrowserDiagnostics: Codable, Sendable, Equatable {
    public let appName: String
    public let available: Bool
    public let url: String?
    public let title: String?
    public let domain: String?
    public let indexedElementCount: Int
    public let topIndexedLabels: [String]
    public let simplifiedTextPreview: String?

    public init(
        appName: String,
        available: Bool,
        url: String? = nil,
        title: String? = nil,
        domain: String? = nil,
        indexedElementCount: Int,
        topIndexedLabels: [String],
        simplifiedTextPreview: String? = nil
    ) {
        self.appName = appName
        self.available = available
        self.url = url
        self.title = title
        self.domain = domain
        self.indexedElementCount = indexedElementCount
        self.topIndexedLabels = topIndexedLabels
        self.simplifiedTextPreview = simplifiedTextPreview
    }
}

public struct ControllerDiagnosticsSnapshot: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let graph: ControllerGraphDiagnostics
    public let workflows: [ControllerWorkflowDiagnostics]
    public let experiments: [ControllerExperimentDiagnostics]
    public let recovery: ControllerRecoveryDiagnostics
    public let projectMemory: [ControllerProjectMemoryDiagnostics]
    public let architectureFindings: [ControllerArchitectureFindingDiagnostics]
    public let repositoryIndexes: [ControllerRepositoryIndexDiagnostics]
    public let host: ControllerHostDiagnostics?
    public let browser: ControllerBrowserDiagnostics?

    public init(
        generatedAt: Date = Date(),
        graph: ControllerGraphDiagnostics,
        workflows: [ControllerWorkflowDiagnostics],
        experiments: [ControllerExperimentDiagnostics],
        recovery: ControllerRecoveryDiagnostics,
        projectMemory: [ControllerProjectMemoryDiagnostics],
        architectureFindings: [ControllerArchitectureFindingDiagnostics],
        repositoryIndexes: [ControllerRepositoryIndexDiagnostics],
        host: ControllerHostDiagnostics? = nil,
        browser: ControllerBrowserDiagnostics? = nil
    ) {
        self.generatedAt = generatedAt
        self.graph = graph
        self.workflows = workflows
        self.experiments = experiments
        self.recovery = recovery
        self.projectMemory = projectMemory
        self.architectureFindings = architectureFindings
        self.repositoryIndexes = repositoryIndexes
        self.host = host
        self.browser = browser
    }
}

public struct TraceSessionSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let stepCount: Int
    public let lastUpdated: Date?

    public init(id: String, stepCount: Int, lastUpdated: Date?) {
        self.id = id
        self.stepCount = stepCount
        self.lastUpdated = lastUpdated
    }
}

public struct TraceStepViewModel: Codable, Sendable, Equatable, Identifiable {
    public let sessionID: String
    public let stepID: Int
    public let timestamp: Date
    public let toolName: String?
    public let actionName: String
    public let actionTarget: String?
    public let actionText: String?
    public let selectedElementID: String?
    public let selectedElementLabel: String?
    public let candidateScore: Double?
    public let candidateReasons: [String]
    public let preObservationHash: String?
    public let postObservationHash: String?
    public let postcondition: String?
    public let verified: Bool
    public let success: Bool
    public let failureClass: String?
    public let surface: String?
    public let policyMode: String?
    public let protectedOperation: String?
    public let approvalRequestID: String?
    public let approvalOutcome: String?
    public let blockedByPolicy: Bool
    public let appProfile: String?
    public let agentKind: String?
    public let domain: String?
    public let plannerFamily: String?
    public let workspaceRelativePath: String?
    public let commandCategory: String?
    public let commandSummary: String?
    public let repositorySnapshotID: String?
    public let buildResultSummary: String?
    public let testResultSummary: String?
    public let patchID: String?
    public let projectMemoryRefs: [String]
    public let experimentID: String?
    public let candidateID: String?
    public let sandboxPath: String?
    public let selectedCandidate: Bool?
    public let experimentOutcome: String?
    public let architectureFindings: [String]
    public let refactorProposalID: String?
    public let knowledgeTier: String?
    public let elapsedMs: Double
    public let screenshotPath: String?
    public let artifactPaths: [String]
    public let notes: String?

    public var id: String { "\(sessionID)-\(stepID)" }

    public init(
        sessionID: String,
        stepID: Int,
        timestamp: Date,
        toolName: String?,
        actionName: String,
        actionTarget: String?,
        actionText: String?,
        selectedElementID: String?,
        selectedElementLabel: String?,
        candidateScore: Double?,
        candidateReasons: [String],
        preObservationHash: String?,
        postObservationHash: String?,
        postcondition: String?,
        verified: Bool,
        success: Bool,
        failureClass: String?,
        surface: String? = nil,
        policyMode: String? = nil,
        protectedOperation: String? = nil,
        approvalRequestID: String? = nil,
        approvalOutcome: String? = nil,
        blockedByPolicy: Bool = false,
        appProfile: String? = nil,
        agentKind: String? = nil,
        domain: String? = nil,
        plannerFamily: String? = nil,
        workspaceRelativePath: String? = nil,
        commandCategory: String? = nil,
        commandSummary: String? = nil,
        repositorySnapshotID: String? = nil,
        buildResultSummary: String? = nil,
        testResultSummary: String? = nil,
        patchID: String? = nil,
        projectMemoryRefs: [String] = [],
        experimentID: String? = nil,
        candidateID: String? = nil,
        sandboxPath: String? = nil,
        selectedCandidate: Bool? = nil,
        experimentOutcome: String? = nil,
        architectureFindings: [String] = [],
        refactorProposalID: String? = nil,
        knowledgeTier: String? = nil,
        elapsedMs: Double,
        screenshotPath: String?,
        artifactPaths: [String],
        notes: String?
    ) {
        self.sessionID = sessionID
        self.stepID = stepID
        self.timestamp = timestamp
        self.toolName = toolName
        self.actionName = actionName
        self.actionTarget = actionTarget
        self.actionText = actionText
        self.selectedElementID = selectedElementID
        self.selectedElementLabel = selectedElementLabel
        self.candidateScore = candidateScore
        self.candidateReasons = candidateReasons
        self.preObservationHash = preObservationHash
        self.postObservationHash = postObservationHash
        self.postcondition = postcondition
        self.verified = verified
        self.success = success
        self.failureClass = failureClass
        self.surface = surface
        self.policyMode = policyMode
        self.protectedOperation = protectedOperation
        self.approvalRequestID = approvalRequestID
        self.approvalOutcome = approvalOutcome
        self.blockedByPolicy = blockedByPolicy
        self.appProfile = appProfile
        self.agentKind = agentKind
        self.domain = domain
        self.plannerFamily = plannerFamily
        self.workspaceRelativePath = workspaceRelativePath
        self.commandCategory = commandCategory
        self.commandSummary = commandSummary
        self.repositorySnapshotID = repositorySnapshotID
        self.buildResultSummary = buildResultSummary
        self.testResultSummary = testResultSummary
        self.patchID = patchID
        self.projectMemoryRefs = projectMemoryRefs
        self.experimentID = experimentID
        self.candidateID = candidateID
        self.sandboxPath = sandboxPath
        self.selectedCandidate = selectedCandidate
        self.experimentOutcome = experimentOutcome
        self.architectureFindings = architectureFindings
        self.refactorProposalID = refactorProposalID
        self.knowledgeTier = knowledgeTier
        self.elapsedMs = elapsedMs
        self.screenshotPath = screenshotPath
        self.artifactPaths = artifactPaths
        self.notes = notes
    }
}

public struct TraceSessionDetail: Codable, Sendable, Equatable {
    public let summary: TraceSessionSummary
    public let steps: [TraceStepViewModel]

    public init(summary: TraceSessionSummary, steps: [TraceStepViewModel]) {
        self.summary = summary
        self.steps = steps
    }
}

public struct RecipeRunStepResult: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let action: String
    public let success: Bool
    public let durationMs: Int
    public let error: String?
    public let note: String?

    public init(id: Int, action: String, success: Bool, durationMs: Int, error: String? = nil, note: String? = nil) {
        self.id = id
        self.action = action
        self.success = success
        self.durationMs = durationMs
        self.error = error
        self.note = note
    }
}

public struct RecipeRunResultDocument: Codable, Sendable, Equatable {
    public let recipeName: String
    public let success: Bool
    public let stepsCompleted: Int
    public let totalSteps: Int
    public let error: String?
    public let traceSessionID: String?
    public let stepResults: [RecipeRunStepResult]
    public let paused: Bool
    public let pendingApprovalRequestID: String?
    public let resumeToken: String?

    public init(
        recipeName: String,
        success: Bool,
        stepsCompleted: Int,
        totalSteps: Int,
        error: String? = nil,
        traceSessionID: String? = nil,
        stepResults: [RecipeRunStepResult],
        paused: Bool = false,
        pendingApprovalRequestID: String? = nil,
        resumeToken: String? = nil
    ) {
        self.recipeName = recipeName
        self.success = success
        self.stepsCompleted = stepsCompleted
        self.totalSteps = totalSteps
        self.error = error
        self.traceSessionID = traceSessionID
        self.stepResults = stepResults
        self.paused = paused
        self.pendingApprovalRequestID = pendingApprovalRequestID
        self.resumeToken = resumeToken
    }
}

public struct DashboardBootstrap: Codable, Sendable, Equatable {
    public let session: ControllerSession
    public let snapshot: ControlSnapshot?
    public let health: HealthStatus
    public let recipes: [RecipeDocument]
    public let traceSessions: [TraceSessionSummary]
    public let approvals: [ApprovalRequestDocument]
    public let missionControl: MissionControlSnapshot?
    public let chatConversation: ChatConversation?
    public let chatProviderStatus: ChatProviderStatus?

    public init(
        session: ControllerSession,
        snapshot: ControlSnapshot?,
        health: HealthStatus,
        recipes: [RecipeDocument],
        traceSessions: [TraceSessionSummary],
        approvals: [ApprovalRequestDocument],
        missionControl: MissionControlSnapshot? = nil,
        chatConversation: ChatConversation? = nil,
        chatProviderStatus: ChatProviderStatus? = nil
    ) {
        self.session = session
        self.snapshot = snapshot
        self.health = health
        self.recipes = recipes
        self.traceSessions = traceSessions
        self.approvals = approvals
        self.missionControl = missionControl
        self.chatConversation = chatConversation
        self.chatProviderStatus = chatProviderStatus
    }
}


public enum ControllerCodingRunMode: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case interactive
    case autonomous

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .interactive: return "Interactive"
        case .autonomous: return "Autonomous"
        }
    }

    public var colorName: String {
        switch self {
        case .interactive: return "accent"
        case .autonomous: return "purple"
        }
    }
}

public enum StatusBadgeTone: Sendable, Equatable {
    case good
    case warning
    case danger
    case critical
    case neutral
}

public enum ControllerCodingRunStatus: String, Codable, Sendable, Equatable {
    case created
    case retrieving
    case proposing
    case awaitingApproval = "awaiting_approval"
    case validating
    case applied
    case rejected
    case failed
}

extension ControllerCodingRunStatus {
    public var displayName: String {
        switch self {
        case .created: return "Created"
        case .retrieving: return "Retrieving"
        case .proposing: return "Proposing"
        case .awaitingApproval: return "Awaiting Approval"
        case .validating: return "Validating"
        case .applied: return "Applied"
        case .rejected: return "Rejected"
        case .failed: return "Failed"
        }
    }

    public var tone: String {
        switch self {
        case .created, .retrieving, .proposing: return "neutral"
        case .awaitingApproval: return "warning"
        case .validating: return "neutral"
        case .applied: return "good"
        case .rejected: return "danger"
        case .failed: return "danger"
        }
    }
}

public struct ControllerCodingRun: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let repoName: String
    public let repoPath: String
    public let mode: ControllerCodingRunMode
    public var status: ControllerCodingRunStatus
    public let task: String
    public let createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public let approvalRequired: Bool
    public let approvalReasons: [String]

    public init(
        id: String,
        repoName: String,
        repoPath: String,
        mode: ControllerCodingRunMode,
        status: ControllerCodingRunStatus,
        task: String,
        createdAt: Date,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        approvalRequired: Bool,
        approvalReasons: [String] = []
    ) {
        self.id = id
        self.repoName = repoName
        self.repoPath = repoPath
        self.mode = mode
        self.status = status
        self.task = task
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.approvalRequired = approvalRequired
        self.approvalReasons = approvalReasons
    }
}

public struct ControllerCodingRunEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let runID: String
    public let type: String
    public let timestamp: Date
    public let payload: [String: String]

    public init(id: String, runID: String, type: String, timestamp: Date, payload: [String: String] = [:]) {
        self.id = id
        self.runID = runID
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
    }
}

public struct ControllerCodingApprovalDecision: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let runID: String
    public let approved: Bool
    public let reason: String?
    public let timestamp: Date

    public init(id: String = UUID().uuidString, runID: String, approved: Bool, reason: String?, timestamp: Date) {
        self.id = id
        self.runID = runID
        self.approved = approved
        self.reason = reason
        self.timestamp = timestamp
    }
}

public struct ControllerCodingPendingProposal: Codable, Sendable, Equatable {
    public let worker: String
    public let summary: String
    public let diff: String
    public let touchedPaths: [String]
    public let changedLines: Int
    public let warnings: [String]
    public let commandsRequested: [String]
    public let approvalReasons: [String]

    public init(
        worker: String,
        summary: String,
        diff: String,
        touchedPaths: [String],
        changedLines: Int,
        warnings: [String],
        commandsRequested: [String],
        approvalReasons: [String]
    ) {
        self.worker = worker
        self.summary = summary
        self.diff = diff
        self.touchedPaths = touchedPaths
        self.changedLines = changedLines
        self.warnings = warnings
        self.commandsRequested = commandsRequested
        self.approvalReasons = approvalReasons
    }
}

public struct ControllerCodingRunDetail: Codable, Sendable, Equatable {
    public let run: ControllerCodingRun
    public let pendingProposal: ControllerCodingPendingProposal?
    public let events: [ControllerCodingRunEvent]
    public let approvals: [ControllerCodingApprovalDecision]
    public let artifactPaths: [String]

    public init(
        run: ControllerCodingRun,
        pendingProposal: ControllerCodingPendingProposal?,
        events: [ControllerCodingRunEvent],
        approvals: [ControllerCodingApprovalDecision],
        artifactPaths: [String]
    ) {
        self.run = run
        self.pendingProposal = pendingProposal
        self.events = events
        self.approvals = approvals
        self.artifactPaths = artifactPaths
    }
}

extension ControllerCodingRunDetail {
    public var summary: String {
        run.task
    }
}

public struct ControllerCodingRunSubmission: Codable, Sendable, Equatable {
    public let repoPath: String
    public let task: String
    public let mode: ControllerCodingRunMode
    public let retrievalQuery: String?
    public let allowedPaths: [String]
    public let validationCommands: [String]

    public init(
        repoPath: String,
        task: String,
        mode: ControllerCodingRunMode = .interactive,
        retrievalQuery: String? = nil,
        allowedPaths: [String] = [],
        validationCommands: [String] = []
    ) {
        self.repoPath = repoPath
        self.task = task
        self.mode = mode
        self.retrievalQuery = retrievalQuery
        self.allowedPaths = allowedPaths
        self.validationCommands = validationCommands
    }
}
