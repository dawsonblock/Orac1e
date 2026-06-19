import Foundation

public struct DiagnosticsGraphEdge: Codable, Sendable, Equatable, Identifiable {
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

    public init(edge: EdgeTransition, promotionEligible: Bool) {
        id = edge.edgeID
        actionContractID = edge.actionContractID
        fromPlanningStateID = edge.fromPlanningStateID.rawValue
        toPlanningStateID = edge.toPlanningStateID.rawValue
        agentKind = edge.agentKind.rawValue
        domain = edge.domain
        workspaceRelativePath = edge.workspaceRelativePath
        commandCategory = edge.commandCategory
        plannerFamily = edge.plannerFamily
        knowledgeTier = edge.knowledgeTier.rawValue
        attempts = edge.attempts
        successRate = edge.successRate
        averageLatencyMs = edge.averageLatencyMs
        targetAmbiguityRate = edge.targetAmbiguityRate
        rollingSuccessRate = edge.rollingSuccessRate
        recoveryTagged = edge.recoveryTagged
        approvalRequired = edge.approvalRequired
        approvalOutcome = edge.approvalOutcome
        lastSuccessAt = edge.lastSuccessTimestamp.map(Date.init(timeIntervalSince1970:))
        lastAttemptAt = edge.lastAttemptTimestamp.map(Date.init(timeIntervalSince1970:))
        failureHistogram = edge.failureHistogram
        self.promotionEligible = promotionEligible
    }
}

public struct DiagnosticsGraphSnapshot: Codable, Sendable, Equatable {
    public let stableEdges: [DiagnosticsGraphEdge]
    public let candidateEdges: [DiagnosticsGraphEdge]
    public let recoveryEdges: [DiagnosticsGraphEdge]
    public let promotionEligibleCount: Int
    public let promotionsFrozen: Bool
    public let globalSuccessRate: Double

    public init(
        stableEdges: [DiagnosticsGraphEdge],
        candidateEdges: [DiagnosticsGraphEdge],
        recoveryEdges: [DiagnosticsGraphEdge],
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

public struct DiagnosticsWorkflowSummary: Codable, Sendable, Equatable, Identifiable {
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

    public init(plan: WorkflowPlan, stale: Bool) {
        id = plan.id
        goalPattern = plan.goalPattern
        agentKind = plan.agentKind.rawValue
        promotionStatus = plan.promotionStatus.rawValue
        successRate = plan.successRate
        replayValidationSuccess = plan.replayValidationSuccess
        repeatedTraceSegmentCount = plan.repeatedTraceSegmentCount
        stepCount = plan.steps.count
        parameterSlots = plan.parameterSlots
        sourceTraceRefs = plan.sourceTraceRefs
        sourceGraphEdgeRefs = plan.sourceGraphEdgeRefs
        self.stale = stale
    }
}

public struct DiagnosticsExperimentCandidate: Codable, Sendable, Equatable, Identifiable {
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

    public init(result: ExperimentResult) {
        id = result.candidate.id
        title = result.candidate.title
        summary = result.candidate.summary
        workspaceRelativePath = result.candidate.workspaceRelativePath
        hypothesis = result.candidate.hypothesis
        selected = result.selected
        succeeded = result.succeeded
        architectureRiskScore = result.architectureRiskScore
        sandboxPath = result.sandboxPath
        diffSummary = result.diffSummary
        buildSummary = result.commandResults.first(where: { $0.category == .build })?.summary
        testSummary = result.commandResults.first(where: { $0.category == .test })?.summary
        architectureFindings = result.architectureFindings.map(\.title)
    }
}

public struct DiagnosticsExperimentSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let candidateCount: Int
    public let selectedCandidateID: String?
    public let winningSandboxPath: String?
    public let succeededCandidateCount: Int
    public let candidates: [DiagnosticsExperimentCandidate]

    public init(
        id: String,
        candidateCount: Int,
        selectedCandidateID: String?,
        winningSandboxPath: String?,
        succeededCandidateCount: Int,
        candidates: [DiagnosticsExperimentCandidate]
    ) {
        self.id = id
        self.candidateCount = candidateCount
        self.selectedCandidateID = selectedCandidateID
        self.winningSandboxPath = winningSandboxPath
        self.succeededCandidateCount = succeededCandidateCount
        self.candidates = candidates
    }
}

public struct DiagnosticsRecoveryStrategy: Codable, Sendable, Equatable, Identifiable {
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

public struct DiagnosticsRecoverySnapshot: Codable, Sendable, Equatable {
    public let recoveryStepCount: Int
    public let strategies: [DiagnosticsRecoveryStrategy]

    public init(recoveryStepCount: Int, strategies: [DiagnosticsRecoveryStrategy]) {
        self.recoveryStepCount = recoveryStepCount
        self.strategies = strategies
    }
}

public struct DiagnosticsProjectMemoryRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let kind: String
    public let knowledgeClass: String
    public let status: String
    public let path: String
    public let affectedModules: [String]
    public let evidenceRefs: [String]

    public init(record: ProjectMemoryRecord) {
        id = record.id
        title = record.title
        summary = record.summary
        kind = record.kind.rawValue
        knowledgeClass = record.knowledgeClass.rawValue
        status = record.status.rawValue
        path = record.path
        affectedModules = record.affectedModules
        evidenceRefs = record.evidenceRefs
    }
}

public struct DiagnosticsArchitectureFinding: Codable, Sendable, Equatable, Identifiable {
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
        governanceRuleID: String?
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

public struct DiagnosticsRepositoryIndex: Codable, Sendable, Equatable, Identifiable {
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

    public init(snapshot: RepositorySnapshot) {
        id = snapshot.id
        workspaceRoot = snapshot.workspaceRoot
        buildTool = snapshot.buildTool.rawValue
        activeBranch = snapshot.activeBranch
        isGitDirty = snapshot.isGitDirty
        indexedAt = snapshot.indexedAt
        fileCount = snapshot.indexDiagnostics.fileCount
        symbolCount = snapshot.indexDiagnostics.symbolCount
        dependencyCount = snapshot.indexDiagnostics.dependencyCount
        callEdgeCount = snapshot.indexDiagnostics.callEdgeCount
        testEdgeCount = snapshot.indexDiagnostics.testEdgeCount
        buildTargetCount = snapshot.indexDiagnostics.buildTargetCount
        topSymbols = snapshot.symbolGraph.nodes.prefix(8).map(\.name)
        buildTargets = snapshot.buildGraph.targets.prefix(8).map(\.name)
        topTests = snapshot.testGraph.tests.prefix(8).map(\.name)
    }
}

public struct DiagnosticsHostWindow: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let appName: String
    public let title: String?
    public let elementCount: Int
    public let focused: Bool

    public init(window: HostWindowSnapshot) {
        id = window.id
        appName = window.appName
        title = window.title
        elementCount = window.elementCount
        focused = window.focused
    }
}

public struct DiagnosticsHostSnapshot: Codable, Sendable, Equatable {
    public let snapshotID: String
    public let activeApplication: String?
    public let accessibilityGranted: Bool
    public let screenRecordingGranted: Bool
    public let windowCount: Int
    public let menuCount: Int
    public let dialogTitle: String?
    public let capturedWindowTitle: String?
    public let windows: [DiagnosticsHostWindow]

    public init(snapshot: HostSnapshot) {
        snapshotID = snapshot.snapshotID
        activeApplication = snapshot.activeApplication?.localizedName
        accessibilityGranted = snapshot.permissions.accessibilityGranted
        screenRecordingGranted = snapshot.permissions.screenRecordingGranted
        windowCount = snapshot.windows.count
        menuCount = snapshot.menus.count
        dialogTitle = snapshot.dialog?.title
        capturedWindowTitle = snapshot.capture?.windowTitle
        windows = snapshot.windows.map(DiagnosticsHostWindow.init)
    }
}

public struct DiagnosticsBrowserSnapshot: Codable, Sendable, Equatable {
    public let appName: String
    public let available: Bool
    public let url: String?
    public let title: String?
    public let domain: String?
    public let indexedElementCount: Int
    public let topIndexedLabels: [String]
    public let simplifiedTextPreview: String?

    public init(session: BrowserSession) {
        appName = session.appName
        available = session.available
        url = session.page?.url
        title = session.page?.title
        domain = session.page?.domain
        indexedElementCount = session.page?.indexedElements.count ?? 0
        topIndexedLabels = session.page?.indexedElements.prefix(8).compactMap(\.label) ?? []
        simplifiedTextPreview = session.page?.simplifiedText
    }
}

public struct RuntimeDiagnosticsSnapshot: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let graph: DiagnosticsGraphSnapshot
    public let workflows: [DiagnosticsWorkflowSummary]
    public let experiments: [DiagnosticsExperimentSummary]
    public let recovery: DiagnosticsRecoverySnapshot
    public let projectMemory: [DiagnosticsProjectMemoryRecord]
    public let architectureFindings: [DiagnosticsArchitectureFinding]
    public let repositoryIndexes: [DiagnosticsRepositoryIndex]
    public let host: DiagnosticsHostSnapshot?
    public let browser: DiagnosticsBrowserSnapshot?

    public init(
        generatedAt: Date = Date(),
        graph: DiagnosticsGraphSnapshot,
        workflows: [DiagnosticsWorkflowSummary],
        experiments: [DiagnosticsExperimentSummary],
        recovery: DiagnosticsRecoverySnapshot,
        projectMemory: [DiagnosticsProjectMemoryRecord],
        architectureFindings: [DiagnosticsArchitectureFinding],
        repositoryIndexes: [DiagnosticsRepositoryIndex],
        host: DiagnosticsHostSnapshot? = nil,
        browser: DiagnosticsBrowserSnapshot? = nil
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

public struct RuntimeDiagnosticsBuilder: Sendable {
    private let promotionPolicy: GraphPromotionPolicy
    private let workflowSynthesizer: WorkflowSynthesizer
    private let workflowDecayPolicy: WorkflowDecayPolicy

    public init(
        promotionPolicy: GraphPromotionPolicy = GraphPromotionPolicy(),
        workflowSynthesizer: WorkflowSynthesizer = WorkflowSynthesizer(),
        workflowDecayPolicy: WorkflowDecayPolicy = WorkflowDecayPolicy()
    ) {
        self.promotionPolicy = promotionPolicy
        self.workflowSynthesizer = workflowSynthesizer
        self.workflowDecayPolicy = workflowDecayPolicy
    }

    public func loadTraceEvents(
        from sessionsDirectory: URL = ExperienceStore.resolveSessionsDirectory()
    ) -> [TraceEvent] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { fileURL -> [TraceEvent] in
                guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    return []
                }
                return contents
                    .split(separator: "\n")
                    .compactMap { try? decoder.decode(TraceEvent.self, from: Data($0.utf8)) }
            }
    }

    public func build(
        graphStore: GraphStore,
        traceEvents: [TraceEvent],
        hostSnapshot: HostSnapshot? = nil,
        browserSession: BrowserSession? = nil
    ) -> RuntimeDiagnosticsSnapshot {
        let graph = buildGraphSnapshot(graphStore: graphStore)
        let workflows = buildWorkflowSummaries(traceEvents: traceEvents)
        let experiments = buildExperimentSummaries(traceEvents: traceEvents)
        let recovery = buildRecoverySnapshot(traceEvents: traceEvents)
        let projectMemory = buildProjectMemoryRecords(traceEvents: traceEvents)
        let architectureFindings = buildArchitectureFindings(
            traceEvents: traceEvents,
            experiments: experiments
        )
        let repositoryIndexes = buildRepositoryIndexes(traceEvents: traceEvents)

        return RuntimeDiagnosticsSnapshot(
            graph: graph,
            workflows: workflows,
            experiments: experiments,
            recovery: recovery,
            projectMemory: projectMemory,
            architectureFindings: architectureFindings,
            repositoryIndexes: repositoryIndexes,
            host: hostSnapshot.map(DiagnosticsHostSnapshot.init),
            browser: browserSession.map(DiagnosticsBrowserSnapshot.init)
        )
    }

    private func buildGraphSnapshot(graphStore: GraphStore) -> DiagnosticsGraphSnapshot {
        let globalSuccessRate = graphStore.globalSuccessRate()
        let promotionsFrozen = promotionPolicy.promotionsFrozen(globalVerifiedSuccessRate: globalSuccessRate)
        let stableEdges = graphStore.allStableEdges()
            .map { DiagnosticsGraphEdge(edge: $0, promotionEligible: false) }
        let candidateTransitions = graphStore.allCandidateEdges()
        let candidateEdges = candidateTransitions
            .filter { $0.knowledgeTier == .candidate || $0.knowledgeTier == .exploration }
            .map {
                DiagnosticsGraphEdge(
                    edge: $0,
                    promotionEligible: !promotionsFrozen && promotionPolicy.shouldPromote(edge: $0, now: Date())
                )
            }
        let recoveryEdges = candidateTransitions
            .filter { $0.knowledgeTier == .recovery || $0.recoveryTagged }
            .map { DiagnosticsGraphEdge(edge: $0, promotionEligible: false) }

        return DiagnosticsGraphSnapshot(
            stableEdges: stableEdges,
            candidateEdges: candidateEdges,
            recoveryEdges: recoveryEdges,
            promotionEligibleCount: candidateEdges.filter(\.promotionEligible).count,
            promotionsFrozen: promotionsFrozen,
            globalSuccessRate: globalSuccessRate
        )
    }

    private func buildWorkflowSummaries(traceEvents: [TraceEvent]) -> [DiagnosticsWorkflowSummary] {
        let repeated = TraceSegmenter.repeatedSegments(events: traceEvents)

        return repeated.compactMap { group in
            let goalPattern = group.segments.first?.events.map(\.actionName).joined(separator: " -> ") ?? group.fingerprint
            guard let plan = workflowSynthesizer
                .synthesize(goalPattern: goalPattern, events: group.segments.flatMap(\.events))
                .first
            else {
                return nil
            }

            return DiagnosticsWorkflowSummary(
                plan: plan,
                stale: workflowDecayPolicy.isStale(plan)
            )
        }
        .sorted { lhs, rhs in
            if lhs.promotionStatus == rhs.promotionStatus {
                return lhs.goalPattern < rhs.goalPattern
            }
            return lhs.promotionStatus < rhs.promotionStatus
        }
    }

    private func buildExperimentSummaries(traceEvents: [TraceEvent]) -> [DiagnosticsExperimentSummary] {
        let persistedResults = loadPersistedExperimentResults(traceEvents: traceEvents)
        let groupedResults = Dictionary(grouping: persistedResults, by: \.experimentID)
        if !groupedResults.isEmpty {
            return groupedResults.keys.sorted().compactMap { experimentID in
                guard let results = groupedResults[experimentID] else { return nil }
                let candidates = results
                    .map(DiagnosticsExperimentCandidate.init)
                    .sorted { lhs, rhs in lhs.title < rhs.title }
                return DiagnosticsExperimentSummary(
                    id: experimentID,
                    candidateCount: candidates.count,
                    selectedCandidateID: candidates.first(where: \.selected)?.id,
                    winningSandboxPath: candidates.first(where: \.selected)?.sandboxPath,
                    succeededCandidateCount: candidates.filter(\.succeeded).count,
                    candidates: candidates
                )
            }
        }

        let groupedEvents = Dictionary(grouping: traceEvents.compactMap { event -> TraceEvent? in
            guard event.experimentID != nil else { return nil }
            return event
        }) { $0.experimentID ?? "unknown" }

        return groupedEvents.keys.sorted().map { experimentID in
            let events = groupedEvents[experimentID] ?? []
            let candidates = Dictionary(grouping: events, by: { $0.candidateID ?? $0.patchID ?? "\($0.stepID)" })
                .keys.sorted()
                .map { candidateID -> DiagnosticsExperimentCandidate in
                    let candidateEvents = candidatesEvents(events: events, candidateID: candidateID)
                    let selected = candidateEvents.contains { $0.selectedCandidate == true }
                    return DiagnosticsExperimentCandidate(
                        result: ExperimentResult(
                            experimentID: experimentID,
                            candidate: CandidatePatch(
                                id: candidateID,
                                title: candidateEvents.last?.patchID ?? candidateID,
                                summary: candidateEvents.last?.commandSummary ?? "trace-derived candidate",
                                workspaceRelativePath: candidateEvents.last?.workspaceRelativePath ?? "workspace",
                                content: "",
                                hypothesis: candidateEvents.last?.notes
                            ),
                            sandboxPath: candidateEvents.last?.sandboxPath ?? "",
                            commandResults: [],
                            diffSummary: candidateEvents.last?.notes ?? "",
                            architectureRiskScore: Double(candidateEvents.last?.architectureFindings?.count ?? 0) / 10,
                            architectureFindings: [],
                            refactorProposalID: candidateEvents.last?.refactorProposalID,
                            selected: selected
                        )
                    )
                }

            return DiagnosticsExperimentSummary(
                id: experimentID,
                candidateCount: candidates.count,
                selectedCandidateID: candidates.first(where: \.selected)?.id,
                winningSandboxPath: candidates.first(where: \.selected)?.sandboxPath,
                succeededCandidateCount: candidates.filter(\.succeeded).count,
                candidates: candidates
            )
        }
    }

    private func candidatesEvents(events: [TraceEvent], candidateID: String) -> [TraceEvent] {
        events.filter { ($0.candidateID ?? $0.patchID ?? "\($0.stepID)") == candidateID }
            .sorted { $0.stepID < $1.stepID }
    }

    private func loadPersistedExperimentResults(traceEvents: [TraceEvent]) -> [ExperimentResult] {
        let roots = Set(traceEvents.compactMap { workspaceRoot(fromSandboxPath: $0.sandboxPath) })
        let fileManager = FileManager.default
        let decoder = JSONDecoder()

        return roots.sorted { $0.path < $1.path }.flatMap { workspaceRoot -> [ExperimentResult] in
            let experimentsRoot = workspaceRoot.appendingPathComponent(".oracle/experiments", isDirectory: true)
            guard fileManager.fileExists(atPath: experimentsRoot.path),
                  let directories = try? fileManager.contentsOfDirectory(
                      at: experimentsRoot,
                      includingPropertiesForKeys: nil,
                      options: [.skipsHiddenFiles]
                  )
            else {
                return []
            }

            return directories.compactMap { directory -> [ExperimentResult]? in
                let resultsURL = directory.appendingPathComponent("results.json", isDirectory: false)
                guard let data = try? Data(contentsOf: resultsURL),
                      let results = try? decoder.decode([ExperimentResult].self, from: data)
                else {
                    return nil
                }
                return results
            }
            .flatMap { $0 }
        }
    }

    private func workspaceRoot(fromSandboxPath sandboxPath: String?) -> URL? {
        guard let sandboxPath,
              let range = sandboxPath.range(of: "/.oracle/experiments/")
        else {
            return nil
        }
        return URL(fileURLWithPath: String(sandboxPath[..<range.lowerBound]), isDirectory: true)
    }

    private func buildRecoverySnapshot(traceEvents: [TraceEvent]) -> DiagnosticsRecoverySnapshot {
        let recoveryEvents = traceEvents.filter { $0.recoveryTagged == true || $0.plannerSource == PlannerSource.recovery.rawValue }
        let grouped = Dictionary(grouping: recoveryEvents, by: { $0.recoveryStrategy ?? "recovery" })

        let strategies = grouped.keys.sorted().map { name in
            let events = grouped[name] ?? []
            let successes = events.filter(\.success).count
            let failures = events.count - successes
            let histogram = Dictionary(events.compactMap { $0.failureClass }.map { ($0, 1) }, uniquingKeysWith: +)
            return DiagnosticsRecoveryStrategy(
                id: name,
                attempts: events.count,
                successes: successes,
                failures: failures,
                failureHistogram: histogram
            )
        }

        return DiagnosticsRecoverySnapshot(
            recoveryStepCount: recoveryEvents.count,
            strategies: strategies
        )
    }

    private func buildProjectMemoryRecords(traceEvents: [TraceEvent]) -> [DiagnosticsProjectMemoryRecord] {
        let refs = Set(traceEvents.flatMap { $0.projectMemoryRefs ?? [] })
        return refs.compactMap { path -> DiagnosticsProjectMemoryRecord? in
            guard FileManager.default.fileExists(atPath: path),
                  let record = ProjectMemoryIndexer.parseRecord(fileURL: URL(fileURLWithPath: path))
            else {
                return nil
            }
            return DiagnosticsProjectMemoryRecord(record: record)
        }
        .sorted { lhs, rhs in
            if lhs.kind == rhs.kind {
                return lhs.title < rhs.title
            }
            return lhs.kind < rhs.kind
        }
    }

    private func buildArchitectureFindings(
        traceEvents: [TraceEvent],
        experiments: [DiagnosticsExperimentSummary]
    ) -> [DiagnosticsArchitectureFinding] {
        var findings: [String: DiagnosticsArchitectureFinding] = [:]

        for event in traceEvents {
            for summary in event.architectureFindings ?? [] {
                let key = "trace|\(summary)"
                let existing = findings[key]
                findings[key] = DiagnosticsArchitectureFinding(
                    id: existing?.id ?? key,
                    title: existing?.title ?? summary,
                    summary: existing?.summary ?? summary,
                    severity: existing?.severity ?? ArchitectureFindingSeverity.warning.rawValue,
                    affectedModules: existing?.affectedModules ?? [],
                    evidence: existing?.evidence ?? [],
                    riskScore: existing?.riskScore ?? 0.5,
                    occurrences: (existing?.occurrences ?? 0) + 1,
                    governanceRuleID: existing?.governanceRuleID
                )
            }
        }

        for experiment in experiments {
            for candidate in experiment.candidates {
                for findingTitle in candidate.architectureFindings {
                    let key = "experiment|\(findingTitle)"
                    let existing = findings[key]
                    findings[key] = DiagnosticsArchitectureFinding(
                        id: existing?.id ?? key,
                        title: existing?.title ?? findingTitle,
                        summary: existing?.summary ?? findingTitle,
                        severity: existing?.severity ?? ArchitectureFindingSeverity.warning.rawValue,
                        affectedModules: existing?.affectedModules ?? [],
                        evidence: existing?.evidence ?? [experiment.id],
                        riskScore: max(existing?.riskScore ?? 0, candidate.architectureRiskScore),
                        occurrences: (existing?.occurrences ?? 0) + 1,
                        governanceRuleID: existing?.governanceRuleID
                    )
                }
            }
        }

        return findings.values.sorted { lhs, rhs in
            if lhs.occurrences == rhs.occurrences {
                return lhs.title < rhs.title
            }
            return lhs.occurrences > rhs.occurrences
        }
    }

    private func buildRepositoryIndexes(traceEvents: [TraceEvent]) -> [DiagnosticsRepositoryIndex] {
        let roots = Set(traceEvents.compactMap { event -> URL? in
            if let repositorySnapshotID = event.repositorySnapshotID,
               let workspaceRoot = repositorySnapshotID.split(separator: "|", maxSplits: 1).first
            {
                return URL(fileURLWithPath: String(workspaceRoot), isDirectory: true)
            }
            return workspaceRoot(fromSandboxPath: event.sandboxPath)
        })

        let indexer = RepositoryIndexer()
        return roots
            .compactMap { indexer.loadPersistedSnapshot(workspaceRoot: $0) }
            .map(DiagnosticsRepositoryIndex.init)
            .sorted { lhs, rhs in
                if lhs.indexedAt == rhs.indexedAt {
                    return lhs.workspaceRoot < rhs.workspaceRoot
                }
                return lhs.indexedAt > rhs.indexedAt
            }
    }
}
