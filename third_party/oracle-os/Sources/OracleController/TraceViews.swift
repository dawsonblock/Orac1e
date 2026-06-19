import SwiftUI
import OracleControllerShared

struct TracesWorkspaceView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            PanelCard("Sessions", subtitle: "Ordered JSONL traces emitted by the runtime") {
                TextField("Search sessions", text: $store.traceSearchText)
                    .textFieldStyle(.roundedBorder)

                List(store.filteredTraceSessions, selection: $store.selectedTraceSessionID) { session in
                    Button {
                        Task { await store.loadTraceSession(id: session.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.id)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                                Text("\(session.stepCount) step\(session.stepCount == 1 ? "" : "s")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(session.lastUpdated.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(session.id)
                }
                .frame(minHeight: 520)
            }
            .frame(width: 360)

            PanelCard("Steps", subtitle: store.traceDetail?.summary.id ?? "Select a session to inspect step-level evidence") {
                if let traceDetail = store.traceDetail, !traceDetail.steps.isEmpty {
                    List(traceDetail.steps, selection: $store.selectedTraceStepID) { step in
                        Button {
                            store.selectedTraceStepID = step.id
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.actionName.capitalized)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(step.toolName ?? "Runtime")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    StatusBadge(label: step.success ? "Success" : "Failure", tone: step.success ? .good : .danger)
                                    Text("#\(step.stepID)")
                                        .font(.system(size: 11, design: .monospaced))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .tag(step.id)
                    }
                } else {
                    EmptyStateView(
                        systemImage: "doc.text.magnifyingglass",
                        title: "No Trace Loaded",
                        message: "Choose a recorded session to inspect verification, hashes, and failure artifacts."
                    )
                    .frame(height: 420)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
    }
}

struct TraceInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("Trace Step", subtitle: "Action evidence and failure context") {
                    if let step = store.selectedTraceStep {
                        HStack {
                            StatusBadge(label: step.success ? "Success" : "Failure", tone: step.success ? .good : .danger)
                            if let failureClass = step.failureClass {
                                StatusBadge(label: failureClass, tone: .warning)
                            }
                            if let approvalOutcome = step.approvalOutcome {
                                StatusBadge(label: approvalOutcome, tone: approvalOutcome == "approved" ? .good : .warning)
                            }
                        }
                        KVRow(key: "Tool", value: step.toolName ?? "Runtime")
                        KVRow(key: "Action", value: step.actionName)
                        KVRow(key: "Target", value: step.actionTarget ?? "None")
                        KVRow(key: "Surface", value: step.surface ?? "Unknown")
                        if let agentKind = step.agentKind {
                            KVRow(key: "Agent", value: agentKind)
                        }
                        if let plannerFamily = step.plannerFamily {
                            KVRow(key: "Planner", value: plannerFamily)
                        }
                        if let domain = step.domain {
                            KVRow(key: "Domain", value: domain)
                        }
                        if let commandCategory = step.commandCategory {
                            KVRow(key: "Command", value: commandCategory)
                        }
                        if let commandSummary = step.commandSummary {
                            KVRow(key: "Summary", value: commandSummary)
                        }
                        if let workspaceRelativePath = step.workspaceRelativePath {
                            KVRow(key: "Path", value: workspaceRelativePath, monospaced: true)
                        }
                        if let protectedOperation = step.protectedOperation {
                            KVRow(key: "Protected Op", value: protectedOperation)
                        }
                        if let policyMode = step.policyMode {
                            KVRow(key: "Policy Mode", value: policyMode)
                        }
                        if let appProfile = step.appProfile {
                            KVRow(key: "App Profile", value: appProfile)
                        }
                        if let approvalRequestID = step.approvalRequestID {
                            KVRow(key: "Approval", value: approvalRequestID, monospaced: true)
                        }
                        KVRow(key: "Policy Block", value: step.blockedByPolicy ? "Yes" : "No")
                        KVRow(key: "Postcondition", value: step.postcondition ?? "None")
                        KVRow(key: "Pre Hash", value: step.preObservationHash ?? "Unavailable", monospaced: true)
                        KVRow(key: "Post Hash", value: step.postObservationHash ?? "Unavailable", monospaced: true)
                        if let buildResultSummary = step.buildResultSummary {
                            KVRow(key: "Build", value: buildResultSummary)
                        }
                        if let testResultSummary = step.testResultSummary {
                            KVRow(key: "Tests", value: testResultSummary)
                        }
                        if let patchID = step.patchID {
                            KVRow(key: "Patch", value: patchID, monospaced: true)
                        }
                        if let repositorySnapshotID = step.repositorySnapshotID {
                            KVRow(key: "Repo Snapshot", value: repositorySnapshotID, monospaced: true)
                        }
                        if let knowledgeTier = step.knowledgeTier {
                            KVRow(key: "Knowledge Tier", value: knowledgeTier)
                        }
                        if let experimentID = step.experimentID {
                            KVRow(key: "Experiment", value: experimentID, monospaced: true)
                        }
                        if let candidateID = step.candidateID {
                            KVRow(key: "Candidate", value: candidateID, monospaced: true)
                        }
                        if let selectedCandidate = step.selectedCandidate {
                            KVRow(key: "Selected", value: selectedCandidate ? "Yes" : "No")
                        }
                        if let experimentOutcome = step.experimentOutcome {
                            KVRow(key: "Experiment Outcome", value: experimentOutcome)
                        }
                        if let sandboxPath = step.sandboxPath {
                            KVRow(key: "Sandbox", value: sandboxPath, monospaced: true)
                        }
                        if let refactorProposalID = step.refactorProposalID {
                            KVRow(key: "Refactor Proposal", value: refactorProposalID, monospaced: true)
                        }
                        KVRow(key: "Elapsed", value: "\(Int(step.elapsedMs)) ms", monospaced: true)
                        if !step.projectMemoryRefs.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Project Memory")
                                    .font(.system(size: 12, weight: .semibold))
                                ForEach(step.projectMemoryRefs, id: \.self) { ref in
                                    Text(ref)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        if !step.architectureFindings.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Architecture Findings")
                                    .font(.system(size: 12, weight: .semibold))
                                ForEach(step.architectureFindings, id: \.self) { finding in
                                    Text(finding)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        if let notes = step.notes, !notes.isEmpty {
                            Divider()
                            Text(notes)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "waveform.path.ecg.text",
                            title: "No Step Selected",
                            message: "Select a trace step to inspect verification hashes, notes, and artifacts."
                        )
                        .frame(height: 280)
                    }
                }

                PanelCard("Artifacts", subtitle: "Failure notes, observations, and screenshots") {
                    if let step = store.selectedTraceStep, !step.artifactPaths.isEmpty {
                        ForEach(step.artifactPaths, id: \.self) { path in
                            HStack {
                                Text(path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(2)
                                Spacer()
                                Button("Open") {
                                    store.openArtifact(path)
                                }
                                Button("Reveal") {
                                    store.revealArtifact(path)
                                }
                            }
                        }
                    } else {
                        Text("No artifact paths were recorded for this step.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
    }
}
