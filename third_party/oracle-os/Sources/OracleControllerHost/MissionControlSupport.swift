import Foundation
import OracleControllerShared
import OracleOS

extension ControllerRuntimeBridge {
    func chatProviderStatus() -> ChatProviderStatus {
        ClaudeLocalCopilot.status()
    }

    func missionControlSnapshot(appName: String?) -> MissionControlSnapshot {
        let health = healthStatus()
        let diagnostics = diagnosticsSnapshot()
        let snapshot = refreshSnapshot(appName: appName)
        let approvals = listApprovalRequests()
        let traces = listTraceSessions()
        let recentSteps = Array(recordedSteps(since: 0).suffix(8))
        let metrics = runtimeContext.metricsRecorder.current
        let providerStatus = chatProviderStatus()

        return MissionControlSnapshot(
            kpis: buildKPIs(
                health: health,
                diagnostics: diagnostics,
                approvals: approvals,
                metrics: metrics,
                providerStatus: providerStatus
            ),
            latencySeries: latencySeries(from: recentSteps),
            successSeries: successSeries(from: recentSteps),
            workflowSeries: workflowSeries(from: diagnostics.workflows),
            recentActivity: recentActivity(from: recentSteps),
            alerts: buildAlerts(
                health: health,
                diagnostics: diagnostics,
                approvals: approvals,
                traces: traces,
                providerStatus: providerStatus
            ),
            approvals: approvals,
            workflows: Array(diagnostics.workflows.prefix(4)),
            experiments: Array(diagnostics.experiments.prefix(3)),
            traceSessions: Array(traces.prefix(6)),
            repositoryIndexes: Array(diagnostics.repositoryIndexes.prefix(3)),
            health: health,
            snapshot: snapshot,
            host: diagnostics.host,
            browser: diagnostics.browser,
            providerStatus: providerStatus,
            recommendedPrompts: recommendedPrompts(
                health: health,
                approvals: approvals,
                traces: traces,
                providerStatus: providerStatus
            )
        )
    }

    private func buildKPIs(
        health: HealthStatus,
        diagnostics: ControllerDiagnosticsSnapshot,
        approvals: [ApprovalRequestDocument],
        metrics: RuntimeMetrics,
        providerStatus: ChatProviderStatus
    ) -> [DashboardKPI] {
        let readinessValue = health.permissions.allSatisfy(\.granted) && health.controllerConnected ? "Ready" : "Attention"
        let readinessTone: DashboardTone = readinessValue == "Ready" ? .good : .warning
        let successRate = diagnostics.graph.globalSuccessRate > 0 ? diagnostics.graph.globalSuccessRate : metrics.actionSuccessRate
        let avgLatency = averageLatency(from: diagnostics, metrics: metrics)
        let stableWorkflowCount = diagnostics.workflows.filter { $0.promotionStatus.lowercased().contains("promot") || $0.promotionStatus.lowercased().contains("stable") }.count

        return [
            DashboardKPI(
                id: "runtime-readiness",
                title: "Runtime readiness",
                value: readinessValue,
                detail: "\(health.permissions.filter { $0.granted }.count)/\(health.permissions.count) permissions granted",
                tone: readinessTone
            ),
            DashboardKPI(
                id: "verified-success",
                title: "Verified success",
                value: percentage(successRate),
                detail: "Graph-backed success across trusted execution history",
                tone: successRate >= 0.75 ? .good : (successRate >= 0.4 ? .warning : .danger)
            ),
            DashboardKPI(
                id: "avg-latency",
                title: "Average latency",
                value: avgLatency > 0 ? "\(Int(avgLatency)) ms" : "No data",
                detail: "Mean verified step latency",
                tone: avgLatency == 0 ? .neutral : (avgLatency < 1200 ? .good : .warning)
            ),
            DashboardKPI(
                id: "approvals",
                title: "Pending approvals",
                value: "\(approvals.count)",
                detail: approvals.isEmpty ? "No risky actions are blocked" : "Risk-gated actions are waiting for review",
                tone: approvals.isEmpty ? .good : .warning
            ),
            DashboardKPI(
                id: "workflow-reuse",
                title: "Workflow reuse",
                value: "\(stableWorkflowCount)",
                detail: "\(diagnostics.workflows.count) learned workflows detected",
                tone: stableWorkflowCount > 0 ? .good : .neutral
            ),
            DashboardKPI(
                id: "copilot",
                title: "Copilot provider",
                value: providerStatus.state == .ready ? "Ready" : "Setup",
                detail: providerStatus.displayName,
                tone: providerStatus.state == .ready ? .good : .warning
            ),
        ]
    }

    private func averageLatency(from diagnostics: ControllerDiagnosticsSnapshot, metrics: RuntimeMetrics) -> Double {
        let edges = diagnostics.graph.stableEdges + diagnostics.graph.candidateEdges + diagnostics.graph.recoveryEdges
        let latencies = edges.map(\.averageLatencyMs).filter { $0 > 0 }
        if !latencies.isEmpty {
            return latencies.reduce(0, +) / Double(latencies.count)
        }
        return metrics.meanTimePerAction
    }

    private func latencySeries(from steps: [TraceStepViewModel]) -> DashboardSeries {
        DashboardSeries(
            id: "latency",
            title: "Latency",
            subtitle: "Recent verified steps",
            tone: .neutral,
            points: steps.map {
                DashboardSeriesPoint(
                    id: $0.id,
                    label: shortLabel(for: $0.timestamp),
                    value: $0.elapsedMs,
                    detail: $0.actionName
                )
            }
        )
    }

    private func successSeries(from steps: [TraceStepViewModel]) -> DashboardSeries {
        DashboardSeries(
            id: "success",
            title: "Verification",
            subtitle: "Recent step outcomes",
            tone: .good,
            points: steps.map {
                DashboardSeriesPoint(
                    id: "success-\($0.id)",
                    label: shortLabel(for: $0.timestamp),
                    value: $0.success ? 100 : 0,
                    detail: $0.success ? "Verified" : ($0.failureClass ?? "Failed")
                )
            }
        )
    }

    private func workflowSeries(from workflows: [ControllerWorkflowDiagnostics]) -> DashboardSeries {
        DashboardSeries(
            id: "workflow",
            title: "Workflow reuse",
            subtitle: "Top reusable workflow success rates",
            tone: .good,
            points: workflows.prefix(5).map {
                DashboardSeriesPoint(
                    id: $0.id,
                    label: compactWorkflowLabel($0.goalPattern),
                    value: $0.successRate * 100,
                    detail: $0.promotionStatus
                )
            }
        )
    }

    private func recentActivity(from steps: [TraceStepViewModel]) -> [MissionActivityEntry] {
        steps.reversed().map {
            MissionActivityEntry(
                id: $0.id,
                title: $0.actionName.capitalized + ($0.actionTarget.map { " \($0)" } ?? ""),
                subtitle: $0.success ? ($0.notes ?? "Verified execution recorded") : ($0.failureClass ?? "Execution failed"),
                timestamp: $0.timestamp,
                tone: $0.success ? .good : .danger,
                traceSessionID: $0.sessionID,
                traceStepID: $0.stepID
            )
        }
    }

    private func buildAlerts(
        health: HealthStatus,
        diagnostics: ControllerDiagnosticsSnapshot,
        approvals: [ApprovalRequestDocument],
        traces: [TraceSessionSummary],
        providerStatus: ChatProviderStatus
    ) -> [AlertSummary] {
        var alerts: [AlertSummary] = []

        for permission in health.permissions where !permission.granted {
            alerts.append(
                AlertSummary(
                    id: permission.id,
                    title: "\(permission.title) required",
                    message: permission.detail ?? "Grant access in System Settings to unlock the full controller.",
                    severity: .critical,
                    source: "health"
                )
            )
        }

        if !approvals.isEmpty {
            alerts.append(
                AlertSummary(
                    id: "approvals-pending",
                    title: "\(approvals.count) approvals pending",
                    message: "Risk-gated operations are paused until someone reviews them.",
                    severity: .warning,
                    source: "approvals"
                )
            )
        }

        if providerStatus.state != .ready {
            alerts.append(
                AlertSummary(
                    id: "copilot-status",
                    title: "Copilot setup needed",
                    message: providerStatus.detail,
                    severity: .warning,
                    source: "copilot"
                )
            )
        }

        if !health.visionSidecarRunning {
            alerts.append(
                AlertSummary(
                    id: "vision-sidecar",
                    title: "Vision sidecar offline",
                    message: "AX-first control is still available, but vision-assisted workflows are degraded.",
                    severity: .info,
                    source: "vision"
                )
            )
        }

        if traces.isEmpty {
            alerts.append(
                AlertSummary(
                    id: "no-traces",
                    title: "No trace history yet",
                    message: "Run a manual action or recipe to populate execution history and charts.",
                    severity: .info,
                    source: "traces"
                )
            )
        }

        if diagnostics.graph.promotionsFrozen {
            alerts.append(
                AlertSummary(
                    id: "promotions-frozen",
                    title: "Knowledge promotion frozen",
                    message: "Stable graph promotion is frozen until additional trusted evidence is recorded.",
                    severity: .warning,
                    source: "diagnostics"
                )
            )
        }

        return Array(alerts.prefix(6))
    }

    private func recommendedPrompts(
        health: HealthStatus,
        approvals: [ApprovalRequestDocument],
        traces: [TraceSessionSummary],
        providerStatus: ChatProviderStatus
    ) -> [String] {
        var prompts: [String] = []

        if health.permissions.contains(where: { !$0.granted }) {
            prompts.append("What permissions are missing, and what should I fix first?")
        }

        if !approvals.isEmpty {
            prompts.append("Summarize the pending approvals and the safest next step.")
        }

        if !traces.isEmpty {
            prompts.append("What do the latest traces say about runtime reliability?")
        }

        if providerStatus.state != .ready {
            prompts.append("How do I finish copilot setup for Oracle Controller?")
        }

        prompts.append("What should I do next to improve system readiness?")
        return Array(prompts.prefix(4))
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func shortLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func compactWorkflowLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 18 else { return trimmed }
        return String(trimmed.prefix(18)) + "…"
    }
}
