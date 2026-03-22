import AppKit
import Observation
import SwiftUI

@main
struct OracleControllerApp: App {
    @State private var store = ControllerStore()

    var body: some Scene {
        WindowGroup("Oracle Controller") {
            RootView(store: store)
        }
        .commands {
            ControllerCommands(store: store)
        }

        Settings {
            SettingsWorkspaceView(store: store)
                .frame(width: 560, height: 420)
        }
    }
}

private struct ControllerCommands: Commands {
    @Bindable var store: ControllerStore

    var body: some Commands {
        CommandMenu("Oracle Controller") {
            Button("About Oracle Controller") {
                store.showAboutPanel()
            }

            Divider()

            Button("Refresh Snapshot") {
                Task { await store.refreshNow() }
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button(store.autoRefreshEnabled ? "Pause Monitoring" : "Resume Monitoring") {
                store.autoRefreshEnabled.toggle()
                Task { await store.updateMonitoring() }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            sectionButton(.missionControl, shortcut: "1")
            sectionButton(.control, shortcut: "2")
            sectionButton(.recipes, shortcut: "3")
            sectionButton(.traces, shortcut: "4")
            sectionButton(.health, shortcut: "5")
            sectionButton(.settings, shortcut: ",")

            Divider()

            Button("Run Setup Wizard") {
                store.reopenOnboarding()
            }
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
    }

    @ViewBuilder
    private func sectionButton(_ section: WorkspaceSection, shortcut: KeyEquivalent) -> some View {
        Button(section.title) {
            store.selectedSection = section
        }
        .keyboardShortcut(shortcut, modifiers: [.command])
    }
}
