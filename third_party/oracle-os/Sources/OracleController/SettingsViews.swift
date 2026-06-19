import SwiftUI
import OracleControllerShared

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

struct SettingsInspectorView: View {
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
