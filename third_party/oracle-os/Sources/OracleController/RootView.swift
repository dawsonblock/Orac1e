import AppKit
import Foundation
import SwiftUI
import OracleControllerShared

struct RootView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            content
        } detail: {
            CopilotDockView(store: store) {
                inspector
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1440, minHeight: 900)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.92, green: 0.95, blue: 0.98),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .safeAreaInset(edge: .top) {
            ControllerStatusBar(store: store)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await store.refreshNow() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])

                Toggle(isOn: $store.autoRefreshEnabled) {
                    Label("Auto Refresh", systemImage: store.autoRefreshEnabled ? "wave.3.right" : "pause.circle")
                }
                .toggleStyle(.button)
                .onChange(of: store.autoRefreshEnabled) { _, _ in
                    Task { await store.updateMonitoring() }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if store.isBusy {
                ProgressView()
                    .controlSize(.large)
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
        .overlay {
            if store.showOnboarding {
                OnboardingOverlayView(store: store)
            }
        }
        .alert(
            "Controller Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    store.errorMessage = nil
                }
            },
            message: {
                Text(store.errorMessage ?? "")
            }
        )
        .task {
            await store.start()
            await store.updateMonitoring()
        }
        .onChange(of: store.selectedSection) { _, section in
            Task {
                if section == .diagnostics {
                    await store.loadDiagnostics()
                } else if section == .missionControl, store.missionControl == nil {
                    await store.refreshMissionControl()
                }
            }
        }
    }

    private var sidebar: some View {
        List(WorkspaceSection.allCases, selection: $store.selectedSection) { section in
            Label(section.title, systemImage: section.systemImage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .padding(.vertical, 4)
            .tag(section)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if let session = store.session {
                    Text("Session")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(session.id)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                    if let activeAppName = session.activeAppName {
                        StatusBadge(label: activeAppName, tone: .neutral)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.selectedSection {
        case .missionControl:
            MissionControlWorkspaceView(store: store)
        case .control:
            ControlWorkspaceView(store: store)
        case .recipes:
            RecipesWorkspaceView(store: store)
        case .traces:
            TracesWorkspaceView(store: store)
        case .diagnostics:
            DiagnosticsWorkspaceView(store: store)
        case .health:
            HealthWorkspaceView(store: store)
        case .settings:
            SettingsWorkspaceView(store: store)
        case .coding:
            CodingWorkspaceView(store: store)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        switch store.selectedSection {
        case .missionControl:
            MissionControlInspectorView(store: store)
        case .control:
            ControlInspectorView(store: store)
        case .recipes:
            RecipeInspectorView(store: store)
        case .traces:
            TraceInspectorView(store: store)
        case .diagnostics:
            DiagnosticsInspectorView(store: store)
        case .health:
            HealthInspectorView(store: store)
        case .settings:
            SettingsInspectorView(store: store)
        case .coding:
            CodingInspectorView(store: store)
        }
    }
}

private struct OnboardingOverlayView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Oracle Controller Setup")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(store.onboardingStep.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(store.onboardingStep.rawValue + 1) / \(OnboardingStep.allCases.count)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                content

                Divider()

                HStack {
                    Button("Back") {
                        store.retreatOnboarding()
                    }
                    .disabled(store.onboardingStep == .welcome)

                    Spacer()

                    if store.onboardingStep == .ready {
                        Button("Finish") {
                            store.completeOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(store.onboardingStep == .vision ? "Skip for Now" : "Continue") {
                            store.advanceOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(28)
            .frame(width: 760)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 18)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.onboardingStep {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text("Oracle Controller is the packaged local console for Oracle OS. It keeps the existing execution truth path intact while giving you a guided setup, approvals, traces, recipes, and diagnostics in one app.")
                    .font(.system(size: 14))
                onboardingFacts([
                    "Runs local-only and supervised.",
                    "Embeds the controller host inside the app bundle.",
                    "Stores app data under Application Support instead of the repo.",
                ])
            }

        case .accessibility:
            permissionStep(
                title: "Grant Accessibility",
                detail: store.health?.permissions.first(where: { $0.id == "accessibility" })?.detail
                    ?? "Oracle Controller needs Accessibility access to inspect and act on applications.",
                granted: store.health?.permissions.first(where: { $0.id == "accessibility" })?.granted == true,
                buttonTitle: "Open Accessibility Settings",
                action: { store.openAccessibilitySettings() }
            )

        case .screenRecording:
            permissionStep(
                title: "Grant Screen Recording",
                detail: store.health?.permissions.first(where: { $0.id == "screen-recording" })?.detail
                    ?? "Screen Recording powers the live monitor and screenshot-backed diagnostics.",
                granted: store.health?.permissions.first(where: { $0.id == "screen-recording" })?.granted == true,
                buttonTitle: "Open Screen Recording Settings",
                action: { store.openScreenRecordingSettings() }
            )

        case .runtime:
            VStack(alignment: .leading, spacing: 12) {
                onboardingFacts([
                    "Runtime version: \(store.health?.runtimeVersion ?? "Unknown")",
                    "Bundled host: \(store.productStatus?.bundledHelperAvailable == true ? "available" : "missing")",
                    "App bundle mode: \(store.health?.runningFromAppBundle == true ? "enabled" : "development")",
                    "Application Support: \(store.health?.applicationSupportPath ?? store.productStatus?.applicationSupportPath ?? "Unknown")",
                ])

                if let productStatus = store.productStatus, productStatus.migrationStatus.didMigrateAnything {
                    Text("Imported existing controller data so the packaged app can pick up where the developer setup left off.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

        case .vision:
            VStack(alignment: .leading, spacing: 12) {
                Text("Vision is optional. Core Accessibility-based control works immediately once permissions are granted. You can install or repair the packaged vision bootstrap here and enable the sidecar later.")
                    .font(.system(size: 14))
                HStack(spacing: 10) {
                    Button("Install Vision Bootstrap") {
                        Task { await store.installVisionBootstrap() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Repair Vision") {
                        Task { await store.repairVisionBootstrap() }
                    }
                }
                onboardingFacts([
                    "Bundled assets: \(store.productStatus?.bundledVisionBootstrapAvailable == true ? "available" : "missing")",
                    "Installed location: \(store.productStatus?.visionInstallPath ?? "Unknown")",
                    "Installed now: \(store.productStatus?.visionInstalled == true ? "yes" : "no")",
                ])
            }

        case .recipes:
            VStack(alignment: .leading, spacing: 12) {
                Text("The app seeds bundled sample recipes into your personal data directory the first time it launches. Quick-start tasks are then available from the Recipes and Control sections.")
                    .font(.system(size: 14))
                onboardingFacts([
                    "Bundled sample recipes: \(store.productStatus?.bundledSampleRecipesAvailable == true ? "available" : "missing")",
                    "Seeded recipes: \(store.productStatus?.migrationStatus.seededSampleRecipes ?? 0)",
                    "Recipe library path: \(store.health?.recipeDirectoryPath ?? store.productStatus?.recipesPath ?? "Unknown")",
                ])
            }

        case .ready:
            VStack(alignment: .leading, spacing: 12) {
                Text("The packaged controller is ready. You can start with the manual operator console, run a sample recipe, or stay in the health/settings sections until everything is green.")
                    .font(.system(size: 14))
                onboardingFacts([
                    "Quick actions live on the Control page.",
                    "Risky actions still require approval.",
                    "You can reopen this setup flow from the Oracle Controller menu or Settings.",
                ])
            }
        }
    }

    private func permissionStep(
        title: String,
        detail: String,
        granted: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                StatusBadge(label: granted ? "Granted" : "Required", tone: granted ? .good : .warning)
            }
            Text(detail)
                .font(.system(size: 14))
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
    }

    private func onboardingFacts(_ facts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(facts, id: \.self) { fact in
                Label(fact, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(ControllerTheme.accent)
            }
        }
    }
}

private struct ControlWorkspaceView: View {
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

private struct ApprovalQueueCard: View {
    @Bindable var store: ControllerStore

    var body: some View {
        PanelCard("Approvals", subtitle: "Per-action safety gate for risky operations") {
            if store.approvalQueue.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.shield",
                    title: "No Pending Approvals",
                    message: "Blocked or risky actions will appear here for explicit approval."
                )
                .frame(height: 180)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.approvalQueue) { approval in
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
                                    Task { await store.approveApprovalRequest(approval) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ControllerTheme.accent)

                                Button("Reject", role: .destructive) {
                                    Task { await store.rejectApprovalRequest(approval) }
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
    }
}

private struct ActionComposerCard: View {
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

private struct ControlInspectorView: View {
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

private struct RecipesWorkspaceView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            PanelCard("Recipe Library", subtitle: "Existing replayable workflows") {
                TextField("Search recipes", text: $store.recipeSearchText)
                    .textFieldStyle(.roundedBorder)

                List(store.filteredRecipes, selection: $store.selectedRecipeName) { recipe in
                    Button {
                        Task { await store.selectRecipe(named: recipe.name) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name)
                                .font(.system(size: 13, weight: .semibold))
                            Text(recipe.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(recipe.name)
                }
                .frame(minHeight: 420)

                HStack {
                    Button("New") {
                        store.createRecipe()
                    }
                    Button("Duplicate") {
                        store.duplicateSelectedRecipe()
                    }
                    .disabled(store.selectedRecipeName == nil)
                    Button("Delete", role: .destructive) {
                        Task { await store.deleteSelectedRecipe() }
                    }
                    .disabled(store.selectedRecipeName == nil)
                }
            }
            .frame(width: 320)

            RecipeEditorView(store: store)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
    }
}

private struct RecipeEditorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        PanelCard("Recipe Editor", subtitle: "Form editing over the current JSON schema") {
            HStack {
                Picker("Mode", selection: $store.recipeEditorMode) {
                    ForEach(RecipeEditorMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button {
                    Task { await store.saveDraftRecipe() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(ControllerTheme.accent)
            }

            if store.recipeEditorMode == .raw {
                TextEditor(text: $store.rawRecipeText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 520)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ControllerTheme.border, lineWidth: 1)
                    )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Recipe name", text: $store.draftRecipe.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("Description", text: $store.draftRecipe.description)
                            .textFieldStyle(.roundedBorder)
                        TextField("App", text: stringBinding($store.draftRecipe.app))
                            .textFieldStyle(.roundedBorder)
                        TextField("Global failure policy", text: stringBinding($store.draftRecipe.onFailure))
                            .textFieldStyle(.roundedBorder)

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Parameters")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Button("Add Param") {
                                    store.addRecipeParam()
                                }
                            }

                            if let paramKeys = store.draftRecipe.params?.keys.sorted(), !paramKeys.isEmpty {
                                ForEach(paramKeys, id: \.self) { key in
                                    RecipeParameterRow(store: store, paramKey: key)
                                }
                            } else {
                                Text("No parameters defined.")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Steps")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Button("Add Step") {
                                    store.addRecipeStep()
                                }
                            }

                            ForEach(Array(store.draftRecipe.steps.enumerated()), id: \.element.id) { index, step in
                                RecipeStepCard(store: store, stepIndex: index, step: step)
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(minHeight: 520)
            }
        }
    }
}

private struct RecipeParameterRow: View {
    @Bindable var store: ControllerStore
    let paramKey: String

    var body: some View {
        let paramBinding = Binding<RecipeParamDocument>(
            get: { store.draftRecipe.params?[paramKey] ?? RecipeParamDocument(id: paramKey, type: "string", description: "", required: true) },
            set: { updated in
                var params = store.draftRecipe.params ?? [:]
                params[paramKey] = updated
                store.draftRecipe.params = params
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(paramKey)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Remove", role: .destructive) {
                    store.removeRecipeParam(id: paramKey)
                }
            }
            TextField("Type", text: paramBinding.type)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: paramBinding.description)
                .textFieldStyle(.roundedBorder)
            Toggle("Required", isOn: paramBinding.required)
        }
        .padding(12)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RecipeStepCard: View {
    @Bindable var store: ControllerStore
    let stepIndex: Int
    let step: RecipeStepDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Step \(step.id)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Remove", role: .destructive) {
                    store.removeRecipeStep(id: step.id)
                }
            }

            TextField("Action", text: binding(\.action))
                .textFieldStyle(.roundedBorder)
            TextField("Note", text: stringBinding(binding(\.note)))
                .textFieldStyle(.roundedBorder)
            TextField("Failure policy", text: stringBinding(binding(\.onFailure)))
                .textFieldStyle(.roundedBorder)
            TextField(
                "Target contains (advanced locators remain available in raw mode)",
                text: Binding(
                    get: { store.draftRecipe.steps[stepIndex].target?.computedNameContains ?? "" },
                    set: { newValue in
                        var target = store.draftRecipe.steps[stepIndex].target ?? LocatorDocument()
                        target.computedNameContains = newValue.isEmpty ? nil : newValue
                        store.draftRecipe.steps[stepIndex].target = target
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            TextField(
                "Wait after condition",
                text: Binding(
                    get: { store.draftRecipe.steps[stepIndex].waitAfter?.condition ?? "" },
                    set: { newValue in
                        var waitAfter = store.draftRecipe.steps[stepIndex].waitAfter ?? RecipeWaitConditionDocument(condition: newValue)
                        waitAfter.condition = newValue
                        store.draftRecipe.steps[stepIndex].waitAfter = newValue.isEmpty ? nil : waitAfter
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            TextField(
                "Wait after value",
                text: Binding(
                    get: { store.draftRecipe.steps[stepIndex].waitAfter?.value ?? "" },
                    set: { newValue in
                        var waitAfter = store.draftRecipe.steps[stepIndex].waitAfter ?? RecipeWaitConditionDocument(condition: "elementExists")
                        waitAfter.value = newValue.isEmpty ? nil : newValue
                        store.draftRecipe.steps[stepIndex].waitAfter = waitAfter
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RecipeStepDocument, Value>) -> Binding<Value> {
        Binding(
            get: { store.draftRecipe.steps[stepIndex][keyPath: keyPath] },
            set: { store.draftRecipe.steps[stepIndex][keyPath: keyPath] = $0 }
        )
    }
}

private struct RecipeInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("Run Recipe", subtitle: "Execute the selected workflow with explicit parameters") {
                    if let params = store.draftRecipe.params, !params.isEmpty {
                        ForEach(params.keys.sorted(), id: \.self) { key in
                            TextField(
                                key,
                                text: Binding(
                                    get: { store.recipeRunParameters[key] ?? "" },
                                    set: { store.recipeRunParameters[key] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        Text("This recipe does not declare any runtime parameters.")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await store.runSelectedRecipe() }
                    } label: {
                        Label("Run Selected Recipe", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ControllerTheme.accent)
                }

                PanelCard("Last Run", subtitle: "Structured replay results") {
                    if let latestRecipeRun = store.latestRecipeRun {
                        HStack {
                            StatusBadge(
                                label: latestRecipeRun.paused ? "Paused" : (latestRecipeRun.success ? "Succeeded" : "Failed"),
                                tone: latestRecipeRun.paused ? .warning : (latestRecipeRun.success ? .good : .danger)
                            )
                            Text("\(latestRecipeRun.stepsCompleted)/\(latestRecipeRun.totalSteps) steps")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        if let pendingApprovalRequestID = latestRecipeRun.pendingApprovalRequestID {
                            KVRow(key: "Pending Approval", value: pendingApprovalRequestID, monospaced: true)
                        }
                        if let resumeToken = latestRecipeRun.resumeToken {
                            KVRow(key: "Resume Token", value: resumeToken, monospaced: true)
                        }
                        if let error = latestRecipeRun.error {
                            Text(error)
                                .foregroundStyle(ControllerTheme.danger)
                        }
                        ForEach(latestRecipeRun.stepResults) { step in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.action)
                                        .font(.system(size: 12, weight: .semibold))
                                    if let note = step.note {
                                        Text(note)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(step.durationMs) ms")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "play.rectangle.on.rectangle",
                            title: "No Run Yet",
                            message: "Run a recipe to inspect structured results and linked trace output."
                        )
                        .frame(height: 220)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct TracesWorkspaceView: View {
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

private struct TraceInspectorView: View {
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

private struct DiagnosticsWorkspaceView: View {
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

private struct DiagnosticsInspectorView: View {
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

private struct HealthWorkspaceView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("Runtime Health", subtitle: "Permissions, sidecar state, and local configuration") {
                    if let health = store.health {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                            GridRow {
                                KVRow(key: "Runtime", value: health.runtimeVersion)
                                KVRow(key: "Recipes", value: "\(health.recipeCount)")
                            }
                            GridRow {
                                KVRow(key: "Sidecar", value: health.visionSidecarRunning ? "Running" : "Unavailable")
                                KVRow(key: "Model", value: health.visionModelPath ?? "Unknown")
                            }
                            GridRow {
                                KVRow(key: "Policy Mode", value: health.policyMode)
                                KVRow(key: "Controller", value: health.controllerConnected ? "Connected" : "Offline")
                            }
                            GridRow {
                                KVRow(key: "Approval Broker", value: health.approvalBrokerActive ? "Active" : "Offline")
                                KVRow(key: "Claude MCP", value: health.claudeConfigured ? "Configured" : "Missing")
                            }
                            GridRow {
                                KVRow(key: "Bundle Mode", value: health.runningFromAppBundle ? "Packaged App" : "Developer")
                                KVRow(key: "Bundled Host", value: health.bundledHostAvailable ? "Embedded" : "Missing")
                            }
                            GridRow {
                                KVRow(key: "Trace Dir", value: health.traceDirectoryPath)
                                KVRow(key: "Recipe Dir", value: health.recipeDirectoryPath)
                            }
                            GridRow {
                                KVRow(key: "App Support", value: health.applicationSupportPath)
                                KVRow(key: "Logs", value: health.logsDirectoryPath)
                            }
                            GridRow {
                                KVRow(key: "Graph DB", value: health.graphDatabasePath)
                                KVRow(key: "Vision Install", value: health.visionInstallPath)
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "cross.case.fill",
                            title: "No Health Snapshot",
                            message: "Refresh health to inspect permissions, sidecar availability, and runtime directories."
                        )
                        .frame(height: 260)
                    }
                }

                PanelCard("Permissions", subtitle: "System access required for production-grade control") {
                    if let permissions = store.health?.permissions, !permissions.isEmpty {
                        ForEach(permissions) { permission in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(permission.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(permission.detail ?? "")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(label: permission.granted ? "Granted" : "Required", tone: permission.granted ? .good : .warning)
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                PanelCard("Tool Registry", subtitle: "Manifest-discovered tools and current health probes") {
                    if let registry = store.health?.toolRegistry {
                        VStack(alignment: .leading, spacing: 12) {
                            KVRow(key: "Root", value: registry.rootPath, monospaced: true)
                            KVRow(key: "Tools", value: "\(registry.toolCount)")
                            if !registry.capabilities.isEmpty {
                                KVRow(key: "Capabilities", value: registry.capabilities.joined(separator: ", "))
                            }
                            ForEach(registry.tools) { tool in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(tool.name)
                                                .font(.system(size: 13, weight: .semibold))
                                            Text(tool.id)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        StatusBadge(label: tool.healthy ? "Healthy" : "Unreachable", tone: tool.healthy ? .good : .warning)
                                    }
                                    KVRow(key: "Kind", value: tool.kind)
                                    KVRow(key: "Risk", value: tool.riskLevel)
                                    KVRow(key: "Base URL", value: tool.baseURL, monospaced: true)
                                    if !tool.capabilities.isEmpty {
                                        KVRow(key: "Capabilities", value: tool.capabilities.joined(separator: ", "))
                                    }
                                    if let detail = tool.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "shippingbox",
                            title: "No Tool Registry",
                            message: "Tool manifests were not discovered. Set ORACLE_TOOL_MANIFESTS or run from the workspace root."
                        )
                        .frame(height: 220)
                    }
                }

                PanelCard("Product Setup", subtitle: "Packaged runtime, diagnostics, and optional vision bootstrap") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let productStatus = store.productStatus {
                            KVRow(key: "Build", value: "\(productStatus.buildVersion) (\(productStatus.buildNumber))")
                            KVRow(key: "Vision Assets", value: productStatus.bundledVisionBootstrapAvailable ? "Bundled" : "Missing")
                            KVRow(key: "Vision Installed", value: productStatus.visionInstalled ? "Yes" : "No")
                            if !productStatus.migrationStatus.migratedLegacyItems.isEmpty {
                                KVRow(
                                    key: "Imported",
                                    value: productStatus.migrationStatus.migratedLegacyItems.joined(separator: ", ")
                                )
                            }
                        }

                        HStack(spacing: 10) {
                            Button("Install Vision Bootstrap") {
                                Task { await store.installVisionBootstrap() }
                            }
                            Button("Repair Vision") {
                                Task { await store.repairVisionBootstrap() }
                            }
                            Button("Export Diagnostics") {
                                store.exportDiagnostics()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct HealthInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("System Summary", subtitle: "What still blocks a frictionless operator loop") {
                    if let health = store.health {
                        KVRow(key: "Claude MCP", value: health.claudeConfigured ? "Configured" : "Missing")
                        KVRow(key: "Sidecar Version", value: health.visionSidecarVersion ?? "Unknown")
                        KVRow(key: "Approval Broker", value: health.approvalBrokerActive ? "Active" : "Offline")
                        KVRow(key: "Controller", value: health.controllerConnected ? "Connected" : "Offline")
                        KVRow(key: "Policy Mode", value: health.policyMode)
                        KVRow(key: "Tool Root", value: health.toolRegistry?.rootPath ?? "Not Found", monospaced: true)
                        KVRow(key: "Tool Count", value: "\(health.toolRegistry?.toolCount ?? 0)")
                        KVRow(key: "App Support", value: health.applicationSupportPath, monospaced: true)
                        KVRow(key: "Logs", value: health.logsDirectoryPath, monospaced: true)
                        KVRow(key: "Trace Directory", value: health.traceDirectoryPath, monospaced: true)
                        KVRow(key: "Recipe Directory", value: health.recipeDirectoryPath, monospaced: true)
                        KVRow(key: "Project Memory", value: health.projectMemoryDirectoryPath, monospaced: true)
                        KVRow(key: "Experiments", value: health.experimentsDirectoryPath, monospaced: true)
                        KVRow(key: "Graph DB", value: health.graphDatabasePath, monospaced: true)
                    } else {
                        EmptyStateView(
                            systemImage: "stethoscope",
                            title: "No Health Data",
                            message: "Refresh the dashboard to populate controller diagnostics."
                        )
                        .frame(height: 260)
                    }
                }

                if let registry = store.health?.toolRegistry {
                    PanelCard("Tool Health", subtitle: "Discovered manifests and live health checks") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(registry.tools) { tool in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tool.name)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(tool.baseURL)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        if !tool.capabilities.isEmpty {
                                            Text(tool.capabilities.joined(separator: ", "))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    StatusBadge(label: tool.healthy ? "Healthy" : "Unreachable", tone: tool.healthy ? .good : .warning)
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct SettingsWorkspaceView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("Session Settings", subtitle: "Controller-local behavior, not runtime policy") {
                    Toggle("Auto refresh monitoring", isOn: $store.autoRefreshEnabled)
                        .onChange(of: store.autoRefreshEnabled) { _, _ in
                            Task { await store.updateMonitoring() }
                        }
                    TextField("Monitored app", text: $store.monitorAppName)
                        .textFieldStyle(.roundedBorder)
                    Button("Apply Monitor Settings") {
                        Task { await store.updateMonitoring() }
                    }
                }

                PanelCard("Operations", subtitle: "Open runtime storage used by the controller") {
                    Button("Open Trace Directory") {
                        if let path = store.health?.traceDirectoryPath {
                            store.openArtifact(path)
                        }
                    }
                    Button("Open Recipe Directory") {
                        if let path = store.health?.recipeDirectoryPath {
                            store.openArtifact(path)
                        }
                    }
                    Button("Reveal Application Support") {
                        store.revealDataFolder()
                    }
                    Button("Reveal Logs") {
                        store.revealLogsFolder()
                    }
                    Button("Export Diagnostics") {
                        store.exportDiagnostics()
                    }
                    Button("Reset App Data") {
                        store.resetControllerData()
                    }
                }

                PanelCard("Onboarding + Help", subtitle: "Product setup, help, and optional vision bootstrap") {
                    Button("Run Setup Wizard") {
                        store.reopenOnboarding()
                    }
                    Button("Open Help") {
                        store.openHelp()
                    }
                    Button("Open Release Notes") {
                        store.openReleaseNotes()
                    }
                    Button("Install Vision Bootstrap") {
                        Task { await store.installVisionBootstrap() }
                    }
                    Button("Repair Vision Bootstrap") {
                        Task { await store.repairVisionBootstrap() }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct SettingsInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            PanelCard("Controller Session", subtitle: "Host process and active monitor details") {
                if let session = store.session {
                    KVRow(key: "Session ID", value: session.id, monospaced: true)
                    KVRow(key: "Host PID", value: "\(session.hostProcessID)", monospaced: true)
                    KVRow(key: "Active App", value: session.activeAppName ?? "Unknown")
                    KVRow(key: "Started", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                } else {
                    EmptyStateView(
                        systemImage: "switch.2",
                        title: "No Session Yet",
                        message: "The host session will appear here after the controller bootstraps."
                    )
                    .frame(height: 240)
                }
            }
            .padding(20)
        }
    }
}

private func stringBinding(_ source: Binding<String?>, defaultValue: String = "") -> Binding<String> {
    Binding<String>(
        get: { source.wrappedValue ?? defaultValue },
        set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
    )
}
