import SwiftUI
import OracleControllerShared

struct ControlWorkspaceView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                controlStatusRow

                HStack(alignment: .top, spacing: 18) {
                    PanelCard("Live Monitor", subtitle: "Low-frequency screenshot stream") {
                        ScreenshotPreview(screenshot: store.snapshot?.screenshot)
                            .frame(maxWidth: .infinity, minHeight: 420)
                    }
                    .frame(maxWidth: .infinity)

                    ActionComposerCard(store: store)
                        .frame(width: 380)
                }

                HStack(alignment: .top, spacing: 18) {
                    PanelCard("Visible Elements", subtitle: "\(store.filteredElements.count) in current observation") {
                        TextField("Filter elements", text: $store.elementSearchText)
                            .textFieldStyle(.roundedBorder)

                        if store.filteredElements.isEmpty {
                            EmptyStateView(
                                systemImage: "rectangle.dashed",
                                title: "No Elements",
                                message: "Refresh the snapshot or choose another app to inspect visible UI elements."
                            )
                            .frame(height: 220)
                        } else {
                            List(store.filteredElements, selection: $store.selectedElementID) { element in
                                Button {
                                    store.selectedElementID = element.id
                                } label: {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(element.label ?? element.role ?? element.id)
                                                .font(.system(size: 13, weight: .semibold))
                                            Text(element.role ?? element.source)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        StatusBadge(
                                            label: element.focused ? "Focused" : element.source.uppercased(),
                                            tone: element.focused ? .good : .neutral
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                                .tag(element.id)
                            }
                            .frame(minHeight: 280)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    PanelCard("Action Timeline", subtitle: "Recent verified actions") {
                        if store.recentActions.isEmpty {
                            EmptyStateView(
                                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                                title: "No Recent Actions",
                                message: "Run a manual action or recipe to start building an execution timeline."
                            )
                            .frame(height: 220)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.recentActions) { action in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(action.request.displayTitle)
                                                .font(.system(size: 13, weight: .semibold))
                                            Text(action.message ?? "Completed")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 6) {
                                            StatusBadge(label: action.success ? "Verified" : "Failed", tone: action.success ? .good : .danger)
                                            Text("\(Int(action.elapsedMs)) ms")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                    }
                    .frame(width: 360)
                }

                ApprovalQueueCard(store: store)
            }
            .padding(20)
        }
    }

    private var controlStatusRow: some View {
        PanelCard("Operator Console", subtitle: "Supervised local runtime control") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.snapshot?.observation.appName ?? "No app selected")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(store.snapshot?.observation.windowTitle ?? "No active window")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        if let url = store.snapshot?.observation.url {
                            Text(url)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(ControllerTheme.accent)
                                .lineLimit(1)
                        }
                        if let productStatus = store.productStatus {
                            Text("Build \(productStatus.buildVersion) (\(productStatus.buildNumber))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        HStack(spacing: 8) {
                            StatusBadge(
                                label: store.health?.visionSidecarRunning == true ? "Sidecar Ready" : "Sidecar Optional",
                                tone: store.health?.visionSidecarRunning == true ? .good : .warning
                            )
                            StatusBadge(
                                label: store.health?.approvalBrokerActive == true ? "Approval Broker" : "Approvals Offline",
                                tone: store.health?.approvalBrokerActive == true ? .neutral : .warning
                            )
                            StatusBadge(
                                label: store.autoRefreshEnabled ? "Monitoring" : "Paused",
                                tone: store.autoRefreshEnabled ? .neutral : .warning
                            )
                        }
                        if let permissions = store.health?.permissions {
                            HStack(spacing: 8) {
                                ForEach(permissions) { permission in
                                    StatusBadge(
                                        label: permission.granted ? permission.title : "\(permission.title) Required",
                                        tone: permission.granted ? .good : .warning
                                    )
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Run Setup Wizard") {
                        store.reopenOnboarding()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reveal Data Folder") {
                        store.revealDataFolder()
                    }

                    Button("Export Diagnostics") {
                        store.exportDiagnostics()
                    }

                    Button("Open Help") {
                        store.openHelp()
                    }
                }

                if let inlineMessage = store.inlineMessage, !inlineMessage.isEmpty {
                    Text(inlineMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ApprovalQueueCard: View {
    @Bindable var store: ControllerStore

    var body: some View {
        PanelCard("Approvals", subtitle: "Per-action safety gate for risky operations") {
            approvalContent
        }
    }

    @ViewBuilder
    private var approvalContent: some View {
        if store.approvalQueue.isEmpty {
            EmptyStateView(
                systemImage: "checkmark.shield",
                title: "No Pending Approvals",
                message: "Blocked or risky actions will appear here for explicit approval."
            )
            .frame(height: 180)
        } else {
            approvalList(store.approvalQueue)
        }
    }

    @ViewBuilder
    private func approvalList(_ approvals: [ApprovalRequestDocument]) -> some View {
        VStack(spacing: 10) {
            ForEach(approvals) { (approval: ApprovalRequestDocument) in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(approval.displayTitle)
                                .font(.system(size: 13, weight: .semibold))
                            Text(approval.reason)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(label: approval.riskLevel.uppercased(), tone: .warning)
                    }
                    HStack {
                        StatusBadge(label: approval.protectedOperation, tone: .danger)
                        StatusBadge(label: approval.appProtectionProfile, tone: .neutral)
                        if let appName = approval.appName {
                            StatusBadge(label: appName, tone: .neutral)
                        }
                    }
                    HStack {
                        Button("Approve") {
                            let a = approval
                            Task { await store.approveApprovalRequest(a) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ControllerTheme.accent)

                        Button("Reject", role: .destructive) {
                            let a = approval
                            Task { await store.rejectApprovalRequest(a) }
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Text(approval.surface.uppercased())
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

struct ActionComposerCard: View {
    @Bindable var store: ControllerStore

    var body: some View {
        PanelCard("Manual Action", subtitle: "All high-signal controls route through the verified executor") {
            Picker("Action", selection: $store.actionComposer.kind) {
                ForEach(ActionKind.allCases) { kind in
                    Text(kind.rawValue.capitalized).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Group {
                TextField("Target app", text: $store.actionComposer.appName)
                TextField("Window title (optional)", text: $store.actionComposer.windowTitle)
            }
            .textFieldStyle(.roundedBorder)

            switch store.actionComposer.kind {
            case .focus:
                EmptyView()

            case .click:
                TextField("Query / label", text: $store.actionComposer.query)
                    .textFieldStyle(.roundedBorder)
                TextField("Role (optional)", text: $store.actionComposer.role)
                    .textFieldStyle(.roundedBorder)
                TextField("DOM ID (optional)", text: $store.actionComposer.domID)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("X", text: $store.actionComposer.x)
                    TextField("Y", text: $store.actionComposer.y)
                }
                .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Button", text: $store.actionComposer.button)
                    TextField("Count", text: $store.actionComposer.count)
                }
                .textFieldStyle(.roundedBorder)

            case .type:
                TextField("Target field", text: $store.actionComposer.query)
                    .textFieldStyle(.roundedBorder)
                TextField("DOM ID (optional)", text: $store.actionComposer.domID)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $store.actionComposer.text)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(ControllerTheme.border, lineWidth: 1)
                    )
                Toggle("Clear current value before typing", isOn: $store.actionComposer.clearExisting)

            case .press:
                TextField("Key", text: $store.actionComposer.key)
                    .textFieldStyle(.roundedBorder)
                TextField("Modifiers (comma-separated)", text: $store.actionComposer.modifiers)
                    .textFieldStyle(.roundedBorder)

            case .scroll:
                TextField("Direction", text: $store.actionComposer.direction)
                    .textFieldStyle(.roundedBorder)
                TextField("Amount", text: $store.actionComposer.amount)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("X (optional)", text: $store.actionComposer.x)
                    TextField("Y (optional)", text: $store.actionComposer.y)
                }
                .textFieldStyle(.roundedBorder)

            case .wait:
                TextField("Condition", text: $store.actionComposer.waitCondition)
                    .textFieldStyle(.roundedBorder)
                TextField("Value", text: $store.actionComposer.waitValue)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Timeout (s)", text: $store.actionComposer.timeout)
                    TextField("Interval (s)", text: $store.actionComposer.interval)
                }
                .textFieldStyle(.roundedBorder)
            }

            Button {
                Task { await store.submitAction() }
            } label: {
                Label(store.actionComposer.kind == .wait ? "Evaluate Condition" : "Run Action", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ControllerTheme.accent)
        }
    }
}

struct ControlInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("Selected Element", subtitle: "Inspection details for the highlighted control") {
                    if let element = store.selectedElement {
                        KVRow(key: "ID", value: element.id, monospaced: true)
                        KVRow(key: "Label", value: element.label ?? "None")
                        KVRow(key: "Role", value: element.role ?? "None")
                        KVRow(key: "Value", value: element.value ?? "None")
                        KVRow(key: "Source", value: element.source)
                        KVRow(key: "Confidence", value: String(format: "%.2f", element.confidence))
                        KVRow(key: "Frame", value: element.frame.map { "\(Int($0.x)), \(Int($0.y)) - \(Int($0.width))x\(Int($0.height))" } ?? "Unavailable", monospaced: true)
                    } else {
                        EmptyStateView(
                            systemImage: "cursorarrow.motionlines",
                            title: "No Element Selected",
                            message: "Choose a visible element to inspect its identity, source, and confidence."
                        )
                        .frame(height: 240)
                    }
                }

                PanelCard("Verification", subtitle: "Latest action status") {
                    if let result = store.currentActionResult {
                        HStack {
                            StatusBadge(label: result.success ? "Verified" : "Failed", tone: result.success ? .good : .danger)
                            if let failureClass = result.failureClass {
                                StatusBadge(label: failureClass, tone: .warning)
                            }
                            if let approvalStatus = result.approvalStatus {
                                StatusBadge(label: approvalStatus, tone: approvalStatus == "pending" ? .warning : .neutral)
                            }
                        }
                        KVRow(key: "Request", value: result.request.displayTitle)
                        KVRow(key: "Message", value: result.message ?? "No message")
                        KVRow(key: "Elapsed", value: "\(Int(result.elapsedMs)) ms", monospaced: true)
                        if let agentKind = result.agentKind {
                            KVRow(key: "Agent", value: agentKind)
                        }
                        if let plannerFamily = result.plannerFamily {
                            KVRow(key: "Planner", value: plannerFamily)
                        }
                        if let commandCategory = result.commandCategory {
                            KVRow(key: "Command", value: commandCategory)
                        }
                        if let commandSummary = result.commandSummary {
                            KVRow(key: "Summary", value: commandSummary)
                        }
                        if let workspaceRelativePath = result.workspaceRelativePath {
                            KVRow(key: "Path", value: workspaceRelativePath, monospaced: true)
                        }
                        if let buildResultSummary = result.buildResultSummary {
                            KVRow(key: "Build", value: buildResultSummary)
                        }
                        if let testResultSummary = result.testResultSummary {
                            KVRow(key: "Tests", value: testResultSummary)
                        }
                        if let patchID = result.patchID {
                            KVRow(key: "Patch", value: patchID, monospaced: true)
                        }
                        if let protectedOperation = result.protectedOperation {
                            KVRow(key: "Protected Op", value: protectedOperation)
                        }
                        if let appProtectionProfile = result.appProtectionProfile {
                            KVRow(key: "App Profile", value: appProtectionProfile)
                        }
                        if let policyMode = result.policyMode {
                            KVRow(key: "Policy Mode", value: policyMode)
                        }
                        if let approvalRequestID = result.approvalRequestID {
                            KVRow(key: "Approval", value: approvalRequestID, monospaced: true)
                        }
                        if result.blockedByPolicy {
                            KVRow(key: "Policy", value: "Blocked before execution")
                        }
                        if let traceStepID = result.traceStepID {
                            KVRow(key: "Trace Step", value: "#\(traceStepID)", monospaced: true)
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "checkmark.shield",
                            title: "No Verification Yet",
                            message: "Manual actions and recipe runs will surface verification results here."
                        )
                        .frame(height: 220)
                    }
                }
            }
            .padding(20)
        }
    }
}
