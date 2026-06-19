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






