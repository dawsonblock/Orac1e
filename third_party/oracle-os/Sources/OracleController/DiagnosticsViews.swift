import SwiftUI
import OracleControllerShared

struct DiagnosticsWorkspaceView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            if let diagnostics = store.diagnostics {
                VStack(alignment: .leading, spacing: 18) {
                    PanelCard("Runtime Diagnostics", subtitle: "Live graph, workflow, experiment, recovery, memory, and architecture summaries") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                            GridRow {
                                KVRow(key: "Generated", value: diagnostics.generatedAt.formatted(date: .abbreviated, time: .standard))
                                KVRow(key: "Graph Success", value: String(format: "%.2f", diagnostics.graph.globalSuccessRate))
                            }
                            GridRow {
                                KVRow(key: "Stable Edges", value: "\(diagnostics.graph.stableEdges.count)")
                                KVRow(key: "Candidate Edges", value: "\(diagnostics.graph.candidateEdges.count)")
                            }
                            GridRow {
                                KVRow(key: "Workflows", value: "\(diagnostics.workflows.count)")
                                KVRow(key: "Experiments", value: "\(diagnostics.experiments.count)")
                            }
                            GridRow {
                                KVRow(key: "Recovery Steps", value: "\(diagnostics.graph.recoveryStepCount)")
                                KVRow(key: "Project Memory Refs", value: "\(diagnostics.projectMemory.count)")
                            }
                            GridRow {
                                KVRow(key: "Architecture Findings", value: "\(diagnostics.architectureFindings.count)")
                                KVRow(key: "Repo Indexes", value: "\(diagnostics.repositoryIndexes.count)")
                            }
                            GridRow {
                                KVRow(key: "Promotion Eligible", value: "\(diagnostics.graph.promotionEligibleCount)")
                                KVRow(key: "Indexed Targets", value: "\(diagnostics.repositoryIndexes.reduce(0) { $0 + $1.buildTargetCount })")
                            }
                            GridRow {
                                KVRow(key: "Host Snapshot", value: diagnostics.host?.activeApplication ?? "Unavailable")
                                KVRow(key: "Browser Snapshot", value: diagnostics.browser?.domain ?? diagnostics.browser?.appName ?? "Unavailable")
                            }
                        }
                        HStack(spacing: 8) {
                            StatusBadge(
                                label: diagnostics.graph.promotionsFrozen ? "Promotions Frozen" : "Promotions Active",
                                tone: diagnostics.graph.promotionsFrozen ? .warning : .good
                            )
                            StatusBadge(label: "Stable \(diagnostics.graph.stableEdges.count)", tone: .good)
                            StatusBadge(label: "Candidate \(diagnostics.graph.candidateEdges.count)", tone: .neutral)
                            StatusBadge(label: "Recovery \(diagnostics.graph.recoveryEdges.count)", tone: .warning)
                        }
                    }

                    HStack(alignment: .top, spacing: 18) {
                        diagnosticsHostCard(diagnostics)
                        diagnosticsBrowserCard(diagnostics)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        diagnosticsGraphCard(diagnostics)
                        diagnosticsWorkflowCard(diagnostics)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        diagnosticsRepositoryIndexesCard(diagnostics)
                        diagnosticsExperimentCard(diagnostics)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        diagnosticsRecoveryCard(diagnostics)
                        diagnosticsProjectMemoryCard(diagnostics)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        diagnosticsArchitectureCard(diagnostics)
                    }
                }
                .padding(20)
            } else {
                EmptyStateView(
                    systemImage: "chart.xyaxis.line",
                    title: "No Diagnostics Yet",
                    message: "Refresh the controller or run a few actions to populate graph, workflow, repository, experiment, and architecture diagnostics."
                )
                .padding(40)
            }
        }
    }

    private func diagnosticsGraphCard(_ diagnostics: ControllerDiagnosticsSnapshot) -> some View {
        PanelCard("Graph", subtitle: "Stable, candidate, and recovery control knowledge") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stable")
                    .font(.system(size: 12, weight: .semibold))
                diagnosticEdgeList(
                    diagnostics.graph.stableEdges,
                    emptyTitle: "No Stable Edges",
                    emptyMessage: "Repeated verified transitions will appear here after promotion."
                )

                Divider()

                Text("Candidate")
                    .font(.system(size: 12, weight: .semibold))
                diagnosticEdgeList(
                    diagnostics.graph.candidateEdges,
                    emptyTitle: "No Candidate Edges",
                    emptyMessage: "Fresh graph evidence appears here before promotion."
                )

                Divider()

                Text("Recovery")
                    .font(.system(size: 12, weight: .semibold))
                diagnosticEdgeList(
                    diagnostics.graph.recoveryEdges,
                    emptyTitle: "No Recovery Edges",
                    emptyMessage: "Recovery-tagged transitions stay visible and separate here."
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func diagnosticsHostCard(_ diagnostics: ControllerDiagnosticsSnapshot) -> some View {
        PanelCard("Host Automation", subtitle: "Structured app, window, dialog, menu, and permission snapshot") {
            if let host = diagnostics.host {
                VStack(alignment: .leading, spacing: 10) {
                    KVRow(key: "Active App", value: host.activeApplication ?? "Unknown")
                    KVRow(key: "Snapshot", value: host.snapshotID, monospaced: true)
                    KVRow(key: "Windows", value: "\(host.windowCount)")
                    KVRow(key: "Menus", value: "\(host.menuCount)")
                    KVRow(key: "Dialog", value: host.dialogTitle ?? "None")
                    KVRow(key: "Capture", value: host.capturedWindowTitle ?? "None")
                    HStack(spacing: 8) {
                        StatusBadge(label: host.accessibilityGranted ? "Accessibility Granted" : "Accessibility Missing", tone: host.accessibilityGranted ? .good : .warning)
                        StatusBadge(label: host.screenRecordingGranted ? "Screen Recording Granted" : "Screen Recording Missing", tone: host.screenRecordingGranted ? .good : .warning)
                    }
                    if !host.windows.isEmpty {
                        Divider()
                        ForEach(host.windows.prefix(4)) { window in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(window.title ?? window.appName)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(window.appName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(label: "\(window.elementCount) elements", tone: window.focused ? .good : .neutral)
                            }
                        }
                    }
                }
            } else {
                EmptyStateView(
                    systemImage: "macwindow",
                    title: "No Host Snapshot",
                    message: "The host automation snapshot will appear here once the controller can capture app, window, dialog, and permission state."
                )
                .frame(height: 220)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func diagnosticsBrowserCard(_ diagnostics: ControllerDiagnosticsSnapshot) -> some View {
        PanelCard("Browser Automation", subtitle: "Flattened DOM, indexed elements, and reduced page context") {
            if let browser = diagnostics.browser {
                VStack(alignment: .leading, spacing: 10) {
                    KVRow(key: "Browser", value: browser.appName)
                    KVRow(key: "Available", value: browser.available ? "Yes" : "No")
                    KVRow(key: "Domain", value: browser.domain ?? "Unknown")
                    KVRow(key: "Title", value: browser.title ?? "Unknown")
                    KVRow(key: "URL", value: browser.url ?? "Unknown", monospaced: true)
                    KVRow(key: "Indexed Elements", value: "\(browser.indexedElementCount)")
                    if !browser.topIndexedLabels.isEmpty {
                        Divider()
                        Text(browser.topIndexedLabels.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let preview = browser.simplifiedTextPreview, !preview.isEmpty {
                        Divider()
                        Text(preview)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                }
            } else {
                EmptyStateView(
                    systemImage: "globe",
                    title: "No Browser Snapshot",
                    message: "Open a supported browser and navigate to a page to populate the DOM-reduced browser snapshot."
                )
                .frame(height: 220)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func diagnosticEdgeList(
        _ edges: [ControllerGraphEdgeDiagnostics],
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        if edges.isEmpty {
            EmptyStateView(systemImage: "point.3.filled.connected.trianglepath.dotted", title: emptyTitle, message: emptyMessage)
                .frame(height: 140)
        } else {
            VStack(spacing: 8) {
                ForEach(edges.prefix(6)) { edge in
                    Button {
                        store.selectedGraphEdgeID = edge.id
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(edge.actionContractID)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                                Text("\(edge.fromPlanningStateID) -> \(edge.toPlanningStateID)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                StatusBadge(label: edge.knowledgeTier, tone: edge.recoveryTagged ? .warning : (edge.knowledgeTier == "stable" ? .good : .neutral))
                                Text(String(format: "%.2f", edge.successRate))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func diagnosticsWorkflowCard(_ diagnostics: ControllerDiagnosticsSnapshot) -> some View {
        PanelCard("Workflows", subtitle: "Promoted and candidate reusable programs") {
            if diagnostics.workflows.isEmpty {
                EmptyStateView(
                    systemImage: "square.stack.3d.up",
                    title: "No Workflow Candidates",
                    message: "Repeated verified traces with strong replay scores will appear here."
                )
                .frame(height: 220)
            } else {
                VStack(spacing: 8) {
                    ForEach(diagnostics.workflows.prefix(8)) { workflow in
                        Button {
                            store.selectedWorkflowID = workflow.id
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(workflow.goalPattern)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(2)
                                    Text("\(workflow.stepCount) steps · \(workflow.repeatedTraceSegmentCount)x repeated")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
                                    StatusBadge(label: workflow.promotionStatus, tone: workflow.promotionStatus == "promoted" ? .good : .neutral)
                                    if workflow.stale {
                                        StatusBadge(label: "stale", tone: .warning)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func diagnosticsRepositoryIndexesCard(_ diagnostics: ControllerDiagnosticsSnapshot) -> some View {
        PanelCard("Repository Intelligence", subtitle: "Persisted symbol, dependency, call, test, and build indexes") {
            if diagnostics.repositoryIndexes.isEmpty {
                EmptyStateView(
                    systemImage: "point.3.connected.trianglepath.dotted",
                    title: "No Repository Indexes",
                    message: "Open a workspace or run code-planning actions to persist repository structure here."
                )
                .frame(height: 220)
            } else {
                VStack(spacing: 8) {
                    ForEach(diagnostics.repositoryIndexes.prefix(6)) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(URL(fileURLWithPath: index.workspaceRoot).lastPathComponent)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(index.workspaceRoot)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
                                    StatusBadge(label: index.buildTool, tone: .neutral)
                                    if let branch = index.activeBranch, !branch.isEmpty {
                                        StatusBadge(label: branch, tone: index.isGitDirty ? .warning : .good)
                                    }
                                }
                            }

                            Text("\(index.fileCount) files · \(index.symbolCount) symbols · \(index.dependencyCount) deps · \(index.callEdgeCount) calls · \(index.testEdgeCount) test edges")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            if !index.buildTargets.isEmpty {
                                Text("Targets: \(index.buildTargets.joined(separator: ", "))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if !index.topSymbols.isEmpty {
                                Text("Symbols: \(index.topSymbols.joined(separator: ", "))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if !index.topTests.isEmpty {
                                Text("Tests: \(index.topTests.joined(separator: ", "))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func diagnosticsExperimentCard(_ diagnostics: ControllerDiagnosticsSnapshot) -> some View {
        PanelCard("Experiments", subtitle: "Bounded patch search and selected winners") {
            if diagnostics.experiments.isEmpty {
                EmptyStateView(
                    systemImage: "testtube.2",
                    title: "No Experiment Runs",
                    message: "Low-confidence code repairs and competing fixes will surface here."
                )
                .frame(height: 220)
            } else {
                VStack(spacing: 8) {
                    ForEach(diagnostics.experiments.prefix(8)) { experiment in
                        Button {
                            store.selectedExperimentID = experiment.id
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(experiment.id)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .lineLimit(1)
                                    Text("\(experiment.succeededCandidateCount) / \(experiment.candidateCount) candidates succeeded")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let selectedCandidateID = experiment.selectedCandidateID {
                                    StatusBadge(label: selectedCandidateID, tone: .good)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func diagnosticsRecoveryCard(_ diagnostics: ControllerDiagnosticsSnapshot) -> some View {
        PanelCard("Recovery", subtitle: "Failure-class routing and verified repair attempts") {
            if diagnostics.recovery.strategies.isEmpty {
                EmptyStateView(
                    systemImage: "arrow.trianglehead.clockwise.rotate.90",
                    title: "No Recovery Data",
                    message: "Recovery strategy stats appear after the runtime resolves failures through the verified path."
                )
                .frame(height: 220)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    KVRow(key: "Recovery Steps", value: "\(diagnostics.recovery.recoveryStepCount)")
                    ForEach(diagnostics.recovery.strategies.prefix(8)) { strategy in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(strategy.id)
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                StatusBadge(label: "\(strategy.successes)/\(strategy.attempts)", tone: strategy.successes > 0 ? .good : .warning)
                            }
                            if !strategy.failureHistogram.isEmpty {
                                Text(strategy.failureHistogram.map { "\($0.key): \($0.value)" }.sorted().joined(separator: " · "))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func diagnosticsProjectMemoryCard(_ diagnostics: ControllerDiagnosticsSnapshot) -> some View {
        PanelCard("Project Memory", subtitle: "Structured reusable engineering knowledge referenced by runtime steps") {
            if diagnostics.projectMemory.isEmpty {
                EmptyStateView(
                    systemImage: "archivebox",
                    title: "No Memory References",
                    message: "Planner and architecture decisions will surface here when runtime traces reference project memory."
                )
                .frame(height: 220)
            } else {
                VStack(spacing: 8) {
                    ForEach(diagnostics.projectMemory.prefix(8)) { record in
                        Button {
                            store.selectedProjectMemoryID = record.id
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(record.summary)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
                                    StatusBadge(label: record.kind, tone: .neutral)
                                    StatusBadge(label: record.status, tone: record.status == "accepted" ? .good : .warning)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func diagnosticsArchitectureCard(_ diagnostics: ControllerDiagnosticsSnapshot) -> some View {
        PanelCard("Architecture Findings", subtitle: "Boundary drift, impact, and risk surfaced by runtime and experiments") {
            if diagnostics.architectureFindings.isEmpty {
                EmptyStateView(
                    systemImage: "building.columns",
                    title: "No Architecture Findings",
                    message: "High-impact changes and experiment candidates will contribute findings here."
                )
                .frame(height: 220)
            } else {
                VStack(spacing: 8) {
                    ForEach(diagnostics.architectureFindings.prefix(8)) { finding in
                        Button {
                            store.selectedArchitectureFindingID = finding.id
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(finding.title)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(finding.summary)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
                                    StatusBadge(label: finding.severity, tone: finding.severity == "critical" ? .danger : .warning)
                                    Text(String(format: "%.2f", finding.riskScore))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct DiagnosticsInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("Selected Graph Edge", subtitle: "Current graph selection, promotion state, and reliability metrics") {
                    if let edge = store.selectedGraphEdge {
                        KVRow(key: "Action", value: edge.actionContractID, monospaced: true)
                        KVRow(key: "From", value: edge.fromPlanningStateID, monospaced: true)
                        KVRow(key: "To", value: edge.toPlanningStateID, monospaced: true)
                        KVRow(key: "Tier", value: edge.knowledgeTier)
                        KVRow(key: "Planner", value: edge.plannerFamily ?? "Unknown")
                        KVRow(key: "Agent", value: edge.agentKind)
                        KVRow(key: "Success", value: String(format: "%.2f", edge.successRate))
                        KVRow(key: "Rolling Success", value: String(format: "%.2f", edge.rollingSuccessRate))
                        KVRow(key: "Ambiguity", value: String(format: "%.2f", edge.targetAmbiguityRate))
                        KVRow(key: "Latency", value: "\(Int(edge.averageLatencyMs)) ms", monospaced: true)
                        KVRow(key: "Attempts", value: "\(edge.attempts)")
                        KVRow(key: "Promotion", value: edge.promotionEligible ? "Eligible" : "Not eligible")
                        if let path = edge.workspaceRelativePath {
                            KVRow(key: "Path", value: path, monospaced: true)
                        }
                        if let commandCategory = edge.commandCategory {
                            KVRow(key: "Command", value: commandCategory)
                        }
                        if !edge.failureHistogram.isEmpty {
                            Divider()
                            Text(edge.failureHistogram.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "point.3.filled.connected.trianglepath.dotted",
                            title: "No Graph Edge Selected",
                            message: "Choose a stable, candidate, or recovery edge from Diagnostics to inspect its metrics."
                        )
                        .frame(height: 220)
                    }
                }

                PanelCard("Selected Workflow", subtitle: "Promotion, replay, and parameter details") {
                    if let workflow = store.selectedWorkflowDiagnostics {
                        KVRow(key: "Goal", value: workflow.goalPattern)
                        KVRow(key: "Agent", value: workflow.agentKind)
                        KVRow(key: "Status", value: workflow.promotionStatus)
                        KVRow(key: "Success", value: String(format: "%.2f", workflow.successRate))
                        KVRow(key: "Replay", value: String(format: "%.2f", workflow.replayValidationSuccess))
                        KVRow(key: "Repeated Segments", value: "\(workflow.repeatedTraceSegmentCount)")
                        KVRow(key: "Steps", value: "\(workflow.stepCount)")
                        KVRow(key: "Stale", value: workflow.stale ? "Yes" : "No")
                        if !workflow.parameterSlots.isEmpty {
                            Divider()
                            Text(workflow.parameterSlots.joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "square.stack.3d.up",
                            title: "No Workflow Selected",
                            message: "Choose a workflow candidate or promoted workflow to inspect replay and parameter metadata."
                        )
                        .frame(height: 220)
                    }
                }

                PanelCard("Selected Experiment", subtitle: "Candidate patches, chosen winner, and sandbox context") {
                    if let experiment = store.selectedExperimentDiagnostics {
                        KVRow(key: "Experiment", value: experiment.id, monospaced: true)
                        KVRow(key: "Candidates", value: "\(experiment.candidateCount)")
                        KVRow(key: "Succeeded", value: "\(experiment.succeededCandidateCount)")
                        KVRow(key: "Winner", value: experiment.selectedCandidateID ?? "None", monospaced: true)
                        if let path = experiment.winningSandboxPath {
                            KVRow(key: "Sandbox", value: path, monospaced: true)
                        }
                        Divider()
                        ForEach(experiment.candidates) { candidate in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(candidate.title)
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    StatusBadge(label: candidate.selected ? "selected" : (candidate.succeeded ? "passed" : "failed"), tone: candidate.selected ? .good : (candidate.succeeded ? .neutral : .danger))
                                }
                                Text(candidate.summary)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                if let buildSummary = candidate.buildSummary {
                                    KVRow(key: "Build", value: buildSummary)
                                }
                                if let testSummary = candidate.testSummary {
                                    KVRow(key: "Tests", value: testSummary)
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "testtube.2",
                            title: "No Experiment Selected",
                            message: "Choose an experiment to inspect its candidates, sandbox paths, and selected winner."
                        )
                        .frame(height: 220)
                    }
                }

                PanelCard("Project Memory and Architecture", subtitle: "Long-horizon engineering context and structural findings") {
                    if let record = store.selectedProjectMemoryDiagnostics {
                        KVRow(key: "Memory", value: record.title)
                        KVRow(key: "Kind", value: record.kind)
                        KVRow(key: "Knowledge", value: record.knowledgeClass)
                        KVRow(key: "Status", value: record.status)
                        KVRow(key: "Path", value: record.path, monospaced: true)
                    }
                    if let finding = store.selectedArchitectureFindingDiagnostics {
                        if store.selectedProjectMemoryDiagnostics != nil {
                            Divider()
                        }
                        KVRow(key: "Finding", value: finding.title)
                        KVRow(key: "Severity", value: finding.severity)
                        KVRow(key: "Risk", value: String(format: "%.2f", finding.riskScore))
                        KVRow(key: "Occurrences", value: "\(finding.occurrences)")
                        if let governanceRuleID = finding.governanceRuleID {
                            KVRow(key: "Governance", value: governanceRuleID)
                        }
                        if !finding.affectedModules.isEmpty {
                            Divider()
                            Text(finding.affectedModules.joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    if store.selectedProjectMemoryDiagnostics == nil && store.selectedArchitectureFindingDiagnostics == nil {
                        EmptyStateView(
                            systemImage: "building.columns",
                            title: "No Diagnostic Selection",
                            message: "Choose project-memory records or architecture findings from Diagnostics to inspect them here."
                        )
                        .frame(height: 220)
                    }
                }
            }
            .padding(20)
        }
    }
}
