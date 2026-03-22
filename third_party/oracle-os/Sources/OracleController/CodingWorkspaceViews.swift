import SwiftUI
import OracleControllerShared

struct CodingWorkspaceView: View {
    @Bindable var store: ControllerStore
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !store.codingRuns.isEmpty {
                    CodingRunsListView(runs: store.codingRuns) { run in
                        store.selectedCodingRunID = run.id
                        Task { await store.loadCodingRunDetail(id: run.id) }
                    }
                } else {
                    EmptyStateView(
                        systemImage: "hammer.circle",
                        title: "No coding runs",
                        message: "Start a coding run to see active and completed tasks here."
                    )
                    .frame(height: 360)
                }
                
                if let codingRunDetail = store.codingRunDetail {
                    CodingRunDetailView(detail: codingRunDetail)
                }
            }
            .padding(20)
        }
    }
}

struct CodingInspectorView: View {
    @Bindable var store: ControllerStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CodingFormView(store: store)
            
            Divider()
            
            CodingControlsView(store: store)
        }
        .padding(16)
    }
}

private struct CodingRunsListView: View {
    let runs: [ControllerCodingRun]
    let onRunSelected: (ControllerCodingRun) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coding Runs")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            
            ForEach(runs) { run in
                CodingRunRow(run: run)
                    .onTapGesture { onRunSelected(run) }
            }
        }
        .padding(16)
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

private struct CodingRunRow: View {
    let run: ControllerCodingRun
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusBadge(
                label: run.status.displayName,
                tone: run.status.tone
            )
            .frame(width: 80)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(run.task)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(run.mode.displayName)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(run.mode.color.opacity(0.2))
                        .cornerRadius(4)
                    
                    Text(run.repoPath.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Text(run.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if run.status == .awaitingApproval {
                Button("Review") {
                    // This would open the detail view
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
    }
}

private struct CodingRunDetailView: View {
    let detail: ControllerCodingRunDetail
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Coding Run Details")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            
            KVRow(key: "Task", value: detail.summary.record.task)
            KVRow(key: "Mode", value: detail.summary.record.mode.displayName)
            KVRow(key: "Repository", value: detail.summary.record.repoPath)
            KVRow(key: "Status", value: detail.summary.record.status.displayName)
            KVRow(key: "Created", value: detail.summary.record.createdAt.formatted(date: .abbreviated, time: .shortened))
            
            if let startedAt = detail.summary.record.startedAt {
                KVRow(key: "Started", value: startedAt.formatted(date: .abbreviated, time: .shortened))
            }
            
            if let completedAt = detail.summary.record.completedAt {
                KVRow(key: "Completed", value: completedAt.formatted(date: .abbreviated, time: .shortened))
            }
            
            if !detail.summary.record.allowedPaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allowed Paths")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(detail.summary.record.allowedPaths, id: \.self) { path in
                        Text(path)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            
            if !detail.summary.record.validationCommands.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Validation Commands")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(detail.summary.record.validationCommands, id: \.self) { command in
                        Text(command)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            
            if let proposal = detail.pendingProposal {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pending Proposal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    Text(proposal.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    Text("Changed Files: \(proposal.touchedPaths.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.5))
                )
            }
            
            if !detail.events.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Events")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(detail.events.prefix(10)) { event in
                        HStack {
                            Text(event.type)
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ControllerTheme.accent.opacity(0.2))
                                .cornerRadius(3)
                            
                            Spacer()
                            
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
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

private struct CodingFormView: View {
    @Bindable var store: ControllerStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start Coding Run")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            
            TextField("Task Description", text: $store.codingTask)
                .textFieldStyle(.roundedBorder)
                .frame(height: 36)
            
            Picker("Mode", selection: $store.codingMode) {
                Text("Interactive").tag(ControllerCodingMode.interactive)
                Text("Autonomous").tag(ControllerCodingMode.autonomous)
            }
            .pickerStyle(.segmented)
            
            TextField("Repository Path", text: $store.codingRepoPath)
                .textFieldStyle(.roundedBorder)
                .frame(height: 36)
            
            TextField("Retrieval Query (optional)", text: $store.codingRetrievalQuery)
                .textFieldStyle(.roundedBorder)
                .frame(height: 36)
            
            TextField("Allowed Paths (comma-separated)", text: $store.codingAllowedPathsText)
                .textFieldStyle(.roundedBorder)
                .frame(height: 36)
            
            TextField("Validation Commands (newline-separated)", text: $store.codingValidationCommandsText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 80)
        }
    }
}

private struct CodingControlsView: View {
    @Bindable var store: ControllerStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                Task { await store.startCodingRun() }
            }) {
                HStack {
                    Image(systemName: "play.circle")
                    Text("Start Coding Run")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.codingTask.isEmpty || store.codingRepoPath.isEmpty)
            
            if let selectedID = store.selectedCodingRunID,
               let run = store.codingRuns.first(where: { $0.id == selectedID }) {
                HStack(spacing: 12) {
                    Button(action: {
                        Task { await store.approveCodingRun(run) }
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("Approve")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    
                    Button(action: {
                        Task { await store.rejectCodingRun(run) }
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("Reject")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .disabled(run.status != .awaitingApproval)
            }
        }
    }
}

private struct KVRow: View {
    let key: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

private struct StatusBadge: View {
    let label: String
    let tone: Tone
    
    enum Tone {
        case neutral, good, warning, danger
    }
    
    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colorForTone(tone).opacity(0.2))
            .cornerRadius(4)
            .foregroundStyle(colorForTone(tone))
    }
    
    private func colorForTone(_ tone: Tone) -> Color {
        switch tone {
        case .neutral: return ControllerTheme.accent
        case .good: return ControllerTheme.success
        case .warning: return ControllerTheme.warning
        case .danger: return ControllerTheme.danger
        }
    }
}

private struct ControllerTheme {
    static let accent = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let border = Color.gray.opacity(0.3)
}
