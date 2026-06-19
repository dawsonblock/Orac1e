import Charts
import SwiftUI
import OracleControllerShared

struct ControllerStatusBar: View {
    @Bindable var store: ControllerStore

    var body: some View {
        HStack(spacing: 12) {
            statusChip("Runtime", runtimeValue, tone: runtimeTone)
            statusChip("Monitor", store.autoRefreshEnabled ? "Active" : "Paused", tone: store.autoRefreshEnabled ? .neutral : .warning)
            statusChip("Copilot", store.chatProviderStatus?.state == .ready ? "Ready" : "Setup", tone: store.chatProviderStatus?.state == .ready ? .good : .warning)
            Spacer()
            if let generatedAt = store.missionControl?.generatedAt {
                Text("Updated \(generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ControllerTheme.border, lineWidth: 1)
        )
    }

    private var runtimeValue: String {
        guard let health = store.health else { return "Loading" }
        return health.permissions.allSatisfy { $0.granted } ? "Ready" : "Needs attention"
    }

    private var runtimeTone: StatusBadge.Tone {
        guard let health = store.health else { return .neutral }
        return health.permissions.allSatisfy { $0.granted } ? .good : .warning
    }

    private func statusChip(_ title: String, _ value: String, tone: StatusBadge.Tone) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            StatusBadge(label: value, tone: tone)
        }
    }
}

struct MissionControlWorkspaceView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let missionControl = store.missionControl {
                    KPIGrid(kpis: missionControl.kpis)

                    HStack(alignment: .top, spacing: 18) {
                        PanelCard("Live Monitor", subtitle: missionControl.snapshot?.observation.windowTitle ?? "Current verified observation") {
                            ScreenshotPreview(screenshot: missionControl.snapshot?.screenshot ?? store.snapshot?.screenshot)
                                .frame(maxWidth: .infinity, minHeight: 340)
                        }
                        .frame(maxWidth: .infinity)

                        MissionAlertsCard(missionControl: missionControl)
                            .frame(width: 360)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        DashboardSeriesCard(series: missionControl.latencySeries, mode: .line)
                        DashboardSeriesCard(series: missionControl.successSeries, mode: .bar)
                        DashboardSeriesCard(series: missionControl.workflowSeries, mode: .bar)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        ActivityTimelineCard(entries: missionControl.recentActivity)
                            .frame(maxWidth: .infinity)
                        WorkflowExperimentCard(workflows: missionControl.workflows, experiments: missionControl.experiments)
                            .frame(width: 420)
                    }
                } else {
                    PanelCard("Mission Control", subtitle: "Loading live controller state") {
                        EmptyStateView(
                            systemImage: "gauge.with.dots.needle.67percent",
                            title: "Mission Control is empty",
                            message: "Refresh the controller to load runtime health, diagnostics, traces, and copilot readiness."
                        )
                        .frame(height: 360)

                        Button("Refresh Mission Control") {
                            Task { await store.refreshMissionControl() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(20)
        }
    }
}

struct MissionControlInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        PanelCard("Mission Control Summary", subtitle: "Current operator posture and copilot guidance") {
            if let missionControl = store.missionControl {
                KVRow(key: "Provider", value: missionControl.providerStatus.displayName)
                KVRow(key: "Provider state", value: missionControl.providerStatus.state.rawValue)
                KVRow(key: "Alerts", value: "\(missionControl.alerts.count)")
                KVRow(key: "Approvals", value: "\(missionControl.approvals.count)")
                KVRow(key: "Trace sessions", value: "\(missionControl.traceSessions.count)")

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommended prompts")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    ForEach(missionControl.recommendedPrompts, id: \.self) { prompt in
                        Text(prompt)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                EmptyStateView(
                    systemImage: "sparkle.magnifyingglass",
                    title: "No mission snapshot",
                    message: "Refresh Mission Control to populate the dashboard summary."
                )
                .frame(height: 220)
            }
        }
        .padding(16)
    }
}

private struct KPIGrid: View {
    let kpis: [DashboardKPI]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(kpis) { kpi in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(kpi.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusBadge(label: kpi.value, tone: tone(for: kpi.tone))
                    }
                    Text(kpi.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(ControllerTheme.border, lineWidth: 1)
                        )
                )
            }
        }
    }

    private func tone(for tone: DashboardTone) -> StatusBadge.Tone {
        switch tone {
        case .neutral: return .neutral
        case .good: return .good
        case .warning: return .warning
        case .danger: return .danger
        }
    }
}

private struct MissionAlertsCard: View {
    let missionControl: MissionControlSnapshot

    var body: some View {
        PanelCard("Alerts & Approvals", subtitle: "High-signal issues that may block operator flow") {
            if missionControl.alerts.isEmpty && missionControl.approvals.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "No active risks",
                    message: "Mission Control is not seeing any blocking alerts or pending approvals."
                )
                .frame(height: 260)
            } else {
                VStack(spacing: 10) {
                    ForEach(missionControl.alerts) { alert in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(alert.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                StatusBadge(label: alert.severity.rawValue.uppercased(), tone: tone(for: alert.severity))
                            }
                            Text(alert.message)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    ForEach(missionControl.approvals.prefix(3)) { approval in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(approval.displayTitle)
                                .font(.system(size: 13, weight: .semibold))
                            Text(approval.reason)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func tone(for severity: AlertSeverity) -> StatusBadge.Tone {
        switch severity {
        case .info: return .neutral
        case .warning: return .warning
        case .critical: return .danger
        }
    }
}

private enum DashboardChartMode {
    case line
    case bar
}

private struct DashboardSeriesCard: View {
    let series: DashboardSeries
    let mode: DashboardChartMode

    var body: some View {
        PanelCard(series.title, subtitle: series.subtitle) {
            if series.points.isEmpty {
                EmptyStateView(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "No chart data",
                    message: "Run actions or recipes to populate this runtime series."
                )
                .frame(height: 240)
            } else {
                Chart(series.points) { point in
                    switch mode {
                    case .line:
                        LineMark(x: .value("Label", point.label), y: .value("Value", point.value))
                            .foregroundStyle(ControllerTheme.accent)
                        AreaMark(x: .value("Label", point.label), y: .value("Value", point.value))
                            .foregroundStyle(ControllerTheme.accent.opacity(0.16))
                    case .bar:
                        BarMark(x: .value("Label", point.label), y: .value("Value", point.value))
                            .foregroundStyle(ControllerTheme.accent.gradient)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(minWidth: 260, minHeight: 220)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActivityTimelineCard: View {
    let entries: [MissionActivityEntry]

    var body: some View {
        PanelCard("Recent Activity", subtitle: "Verified timeline across the current session") {
            if entries.isEmpty {
                EmptyStateView(
                    systemImage: "clock.badge.questionmark",
                    title: "No recent activity",
                    message: "Run a manual action or recipe to generate live activity for Mission Control."
                )
                .frame(height: 260)
            } else {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(color(for: entry.tone))
                                .frame(width: 10, height: 10)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(entry.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func color(for tone: DashboardTone) -> Color {
        switch tone {
        case .neutral: return ControllerTheme.accent
        case .good: return ControllerTheme.success
        case .warning: return ControllerTheme.warning
        case .danger: return ControllerTheme.danger
        }
    }
}

private struct WorkflowExperimentCard: View {
    let workflows: [ControllerWorkflowDiagnostics]
    let experiments: [ControllerExperimentDiagnostics]

    var body: some View {
        PanelCard("Workflows & Experiments", subtitle: "Reusable knowledge and bounded candidates") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Top workflows")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if workflows.isEmpty {
                    Text("No workflows promoted yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(workflows, id: \.id) { workflow in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workflow.goalPattern)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(2)
                                Text(workflow.promotionStatus)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(label: "\(Int(workflow.successRate * 100))%", tone: workflow.successRate >= 0.75 ? .good : .warning)
                        }
                    }
                }

                Divider()

                Text("Recent experiments")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if experiments.isEmpty {
                    Text("No bounded experiments recorded.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(experiments, id: \.id) { experiment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(experiment.id)
                                .font(.system(size: 13, weight: .semibold))
                            Text("Candidates: \(experiment.candidateCount) • Successes: \(experiment.succeededCandidateCount)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
